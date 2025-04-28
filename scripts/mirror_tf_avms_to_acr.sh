#!/bin/bash

set -euo pipefail

CSV_URL="https://azure.github.io/Azure-Verified-Modules/module-indexes/TerraformResourceModules.csv"
ACR_NAME="${ACR_NAME:-myacr.azurecr.io}"
FILTER_MODULES="${FILTER_MODULES:-}"       # Optional comma-separated list to mirror only specific modules
FILTER_VERSIONS="${FILTER_VERSIONS:-}"     # Optional comma-separated list to mirror only specific versions

# Install required tools
command -v curl >/dev/null 2>&1 || { echo >&2 "curl is required but not installed. Exiting."; exit 1; }
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

# Process CSV with awk (skip header)
awk -F',' 'NR > 1 {
  gsub(/^"|"$/, "", $2); module_name=$2
  gsub(/^"|"$/, "", $5); badge=$5
  match(badge, /[0-9]+\.[0-9]+\.[0-9]+/, v);
  if (v[0] != "") {
    print module_name "," v[0]
  }
}' avm_index.csv | while IFS=',' read -r module_name version; do

  echo "🧪 Found module: $module_name version: $version"

  # Filter modules if specified
  if [[ -n "$FILTER_MODULES" && ",$FILTER_MODULES," != *",$module_name,"* ]]; then
    echo "⏭️ Skipping module $module_name (not in FILTER_MODULES)"
    continue
  fi

  # Filter versions if specified
  if [[ -n "$FILTER_VERSIONS" && ",$FILTER_VERSIONS," != *",$version,"* ]]; then
    echo "⏭️ Skipping version $version (not in FILTER_VERSIONS)"
    continue
  fi

  echo "🔄 Mirroring $module_name:$version"

  OCI_PATH="$module_name/azurerm"

  # Pull from GHCR
  oras pull "ghcr.io/azure/$OCI_PATH:$version" -a || { echo "⚠️ Failed to pull $OCI_PATH:$version"; continue; }

  # Push to ACR
  oras push "$ACR_NAME/$OCI_PATH:$version" \
    --artifact-type application/vnd.module.terraform \
    ./*.tf ./*.md || { echo "⚠️ Failed to push $OCI_PATH:$version"; continue; }

  echo "✅ Mirrored: $OCI_PATH:$version"

  # Cleanup local files
  rm -f ./*.tf ./*.md

done

rm -f avm_index.csv

echo "\n✅ All done."
