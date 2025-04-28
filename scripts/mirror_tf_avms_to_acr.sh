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

# Process CSV, skipping the header
 tail -n +2 avm_index.csv | while IFS=',' read -r _ module_name _ _ badge _; do

  # Clean module name and version
  module_name=$(echo "$module_name" | tr -d '"')
  version=$(echo "$badge" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')

  if [[ -z "$module_name" || -z "$version" ]]; then
    continue
  fi

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
