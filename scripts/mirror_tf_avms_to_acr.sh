#!/bin/bash

set -euo pipefail

CSV_URL="https://azure.github.io/Azure-Verified-Modules/module-indexes/TerraformResourceModules.csv"
ACR_NAME="${ACR_NAME:-myacr.azurecr.io}"
FILTER_MODULES="${FILTER_MODULES:-}"       # Optional comma-separated list to mirror only specific modules
FILTER_VERSIONS="${FILTER_VERSIONS:-}"     # Optional comma-separated list to mirror only specific versions (only used if you override latest)

# Install required tools
command -v curl >/dev/null 2>&1 || { echo >&2 "curl is required but not installed. Exiting."; exit 1; }
command -v git >/dev/null 2>&1 || { echo >&2 "git is required but not installed. Exiting."; exit 1; }
command -v oras >/dev/null 2>&1 || { echo >&2 "oras is required but not installed. Exiting."; exit 1; }

# Fetch the CSV
echo "📥 Downloading module index CSV..."
curl -sSL "$CSV_URL" -o avm_index.csv

if [[ ! -s avm_index.csv ]]; then
  echo "❌ Failed to download or empty CSV at $CSV_URL"
  exit 1
fi

# Debug: print the first few lines of the CSV
echo "📄 First few lines of the CSV:"
head -n 10 avm_index.csv

mkdir -p temp_clone

# Process CSV and filter for Available modules with GitHub repos
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

  echo "🧪 Found available module: $module_name"

  # Filter modules if specified
  if [[ -n "$FILTER_MODULES" && ",$FILTER_MODULES," != *",$module_name,"* ]]; then
    echo "⏭️ Skipping module $module_name (not in FILTER_MODULES)"
    continue
  fi

  if [[ -n "$FILTER_VERSIONS" ]]; then
    version="$FILTER_VERSIONS"
  fi

  echo "🔄 Cloning $repo_url to extract module at version: $version"

  pushd temp_clone >/dev/null
  rm -rf "$module_name"
  git clone --depth 1 "$repo_url" "$module_name"
  cd "$module_name"

  echo "📦 Packaging and pushing $module_name:$version"

  OCI_PATH="$module_name/azurerm"

  # Authenticate with ACR for ORAS
  az acr login --name "${ACR_NAME%%.azurecr.io}"

  oras push "$ACR_NAME/$OCI_PATH:$version" \
    --artifact-type application/vnd.module.terraform \
    ./*.tf ./*.md || { echo "⚠️ Failed to push $OCI_PATH:$version"; cd ../.. && continue; }

  echo "✅ Mirrored: $OCI_PATH:$version"

  cd ../..
  rm -rf "temp_clone/$module_name"
  popd >/dev/null

done

rm -f avm_index.csv
rm -rf temp_clone

echo "\n✅ All done."
