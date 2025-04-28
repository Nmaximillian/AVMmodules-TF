#!/bin/bash
set -euo pipefail

CSV_URL="https://azure.github.io/Azure-Verified-Modules/module-indexes/TerraformResourceModules.csv"
ACR_NAME="${ACR_NAME:-myacr.azurecr.io}"
FILTER_MODULES="${FILTER_MODULES:-}"

command -v curl >/dev/null || { echo "❌ curl not found"; exit 1; }
command -v git >/dev/null || { echo "❌ git not found"; exit 1; }
command -v oras >/dev/null || { echo "❌ oras not found"; exit 1; }

echo "📥 Downloading module index CSV..."
curl -sSL "$CSV_URL" -o avm_index.csv

mkdir -p temp_clone

awk -F',' 'NR > 1 {
  gsub(/^"|"$/, "", $5); module_name=$5
  gsub(/^"|"$/, "", $7); status=$7
  gsub(/^"|"$/, "", $8); repo_url=$8
  gsub(/^"|"$/, "", $9); registry_url=$9
  if (status ~ /Available/ && repo_url ~ /^https:\/\/github.com/) {
    n = split(registry_url, parts, "/")
    version = parts[n]
    print module_name "," repo_url "," version
  }
}' avm_index.csv | sort | uniq | while IFS=',' read -r module_name repo_url version; do

  echo "🧪 Found module: $module_name ($version)"

  [[ -n "$FILTER_MODULES" && ",$FILTER_MODULES," != *",$module_name,"* ]] && continue

  echo "🔄 Cloning $repo_url"
  rm -rf "temp_clone/$module_name"
  git clone "$repo_url" "temp_clone/$module_name"

  pushd "temp_clone/$module_name" >/dev/null
  if git rev-parse "v$version" >/dev/null 2>&1; then
    git checkout "v$version"
  elif git rev-parse "$version" >/dev/null 2>&1; then
    git checkout "$version"
  else
    echo "❌ No matching tag for version $version in $module_name"
    popd && continue
  fi

  OCI_PATH="$module_name/azurerm"
  echo "📦 Pushing to $ACR_NAME/$OCI_PATH:$version"
  az acr login --name "${ACR_NAME%%.azurecr.io}"
  oras push "$ACR_NAME/$OCI_PATH:$version" \
    --artifact-type application/vnd.module.terraform \
    ./*.tf ./*.md || echo "⚠️ Failed to push $OCI_PATH:$version"

  popd >/dev/null
done

rm -rf avm_index.csv temp_clone
echo "✅ Done."
