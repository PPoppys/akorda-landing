#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ ! -f "$PROJECT_ROOT/.env.dokploy" ]]; then
  echo "❌ Falta .env.dokploy. Copia .env.dokploy.example y rellénalo."
  exit 1
fi
source "$PROJECT_ROOT/.env.dokploy"

REQUIRED_VARS=(DOKPLOY_URL DOKPLOY_API_KEY PROJECT_NAME ENV_NAME APP_NAME GITHUB_OWNER GITHUB_REPO GITHUB_BRANCH GITHUB_BUILD_PATH GITHUB_ID DOMAIN_HOST DOMAIN_PORT)
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "❌ Variable requerida vacía: $var"
    exit 1
  fi
done

API_BASE="$DOKPLOY_URL/api"
AUTH="x-api-key: $DOKPLOY_API_KEY"
JSON="Content-Type: application/json"

api_post() {
  local path=$1 body=$2
  curl -s -X POST "$API_BASE$path" -H "$AUTH" -H "$JSON" -d "$body"
}
api_get() {
  local path=$1
  curl -s -X GET "$API_BASE$path" -H "$AUTH" -H "$JSON"
}

# 1. Project
echo "📁 Creando proyecto '$PROJECT_NAME'..."
PROJECT_RES=$(api_post "/project.create" "{\"name\":\"$PROJECT_NAME\",\"description\":\"${PROJECT_DESCRIPTION:-}\"}")
PROJECT_ID=$(echo "$PROJECT_RES" | jq -r '.projectId // empty')
if [[ -z "$PROJECT_ID" ]]; then
  PROJECT_ID=$(api_get "/project.all" | jq -r --arg n "$PROJECT_NAME" \
    'if type=="array" then .[] else .items[] end | select(.name==$n) | .projectId' | head -n1)
fi
echo "   ✅ Proyecto: $PROJECT_ID"

# 2. Environment
echo "🌿 Creando entorno '$ENV_NAME'..."
ENV_RES=$(api_post "/environment.create" "{\"name\":\"$ENV_NAME\",\"projectId\":\"$PROJECT_ID\"}")
ENV_ID=$(echo "$ENV_RES" | jq -r '.environmentId // empty')
if [[ -z "$ENV_ID" ]]; then
  ENV_ID=$(api_get "/environment.byProjectId?projectId=$PROJECT_ID" | jq -r --arg n "$ENV_NAME" \
    'if type=="array" then .[] else .items[] end | select(.name==$n) | .environmentId' | head -n1)
fi
echo "   ✅ Entorno: $ENV_ID"

# 3. Application
echo "🚀 Creando aplicación '$APP_NAME'..."
APP_RES=$(api_post "/application.create" "{
  \"name\": \"$APP_NAME\",
  \"appName\": \"$APP_NAME\",
  \"description\": \"${APP_DESCRIPTION:-}\",
  \"environmentId\": \"$ENV_ID\"
}")
APP_ID=$(echo "$APP_RES" | jq -r '.applicationId // empty')
if [[ -z "$APP_ID" ]]; then
  echo "❌ Error creando aplicación."
  echo "$APP_RES"
  exit 1
fi
echo "   ✅ Aplicación: $APP_ID"

# 4. Build Type
echo "🐳 Configurando build type..."
api_post "/application.saveBuildType" "{
  \"applicationId\": \"$APP_ID\",
  \"buildType\": \"dockerfile\",
  \"dockerfile\": \"Dockerfile\",
  \"dockerContextPath\": \"$GITHUB_BUILD_PATH\",
  \"dockerBuildStage\": null,
  \"herokuVersion\": null,
  \"railpackVersion\": null
}" > /dev/null
echo "   ✅ Build type: dockerfile"

# 5. GitHub Provider
echo "🔌 Conectando GitHub..."
api_post "/application.saveGithubProvider" "{
  \"applicationId\": \"$APP_ID\",
  \"repository\": \"$GITHUB_REPO\",
  \"branch\": \"$GITHUB_BRANCH\",
  \"owner\": \"$GITHUB_OWNER\",
  \"buildPath\": \"$GITHUB_BUILD_PATH\",
  \"githubId\": \"$GITHUB_ID\",
  \"triggerType\": \"push\"
}" > /dev/null
echo "   ✅ GitHub: $GITHUB_OWNER/$GITHUB_REPO:$GITHUB_BRANCH"

# 6. Domain
echo "🌐 Creando dominio..."
api_post "/domain.create" "{
  \"applicationId\": \"$APP_ID\",
  \"host\": \"$DOMAIN_HOST\",
  \"port\": $DOMAIN_PORT,
  \"https\": ${DOMAIN_HTTPS:-true},
  \"certificateType\": \"letsencrypt\"
}" > /dev/null
echo "   ✅ Dominio: https://$DOMAIN_HOST"

# 7. Deploy
echo "🚦 Lanzando deploy..."
api_post "/application.deploy" "{\"applicationId\": \"$APP_ID\"}" > /dev/null
echo "   ✅ Deploy iniciado!"

echo ""
echo "========================================"
echo "  🎉 Deploy iniciado!"
echo "========================================"
echo "  Proyecto : $PROJECT_ID"
echo "  App      : $APP_ID"
echo "  URL      : https://$DOMAIN_HOST"
echo "========================================"
