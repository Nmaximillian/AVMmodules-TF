#!/bin/bash

set -euo pipefail

AVM_INDEX_URL="https://azure.github.io/Azure-Verified-Modules/indexes/terraform/tf-resource-modules/"
ACR_NAME="${ACR_NAME:-myacr.azurecr.io}"
FILTER_MODULES="res-app-containerapp" FILTER_VERSIONS="0.2.1" ./scripts/mirror_tf_avms_to_acr.sh
FILTER_VERSIONS="${FILTER_VERSIONS:-}"     # Optional comma-separated list to mirror only specific versions

# Install required tools
command -v jq >/dev/null 2>&1 || { echo >&2 "jq is required but not installed. Exiting."; exit 1; }
command -v curl >/dev/null 2>&1 || { echo >&2 "curl is required but not installed. Exiting."; exit 1; }
command -v oras >/dev/null 2>&1 || { echo >&2 "oras is required but not installed. Exiting."; exit 1; }

# Fetch the module list HTML
echo "Fetching AVM Terraform module list..."
HTML_CONTENT=$(curl -sSL "$AVM_INDEX_URL")

# Extract modules and versions from HTML (grep/sed magic)
echo "$HTML_CONTENT" | grep -oE 'href="[^"]+/"' | \
  sed -E 's/href="([^"]+)\/"/\1/' | \
  sort | uniq | while read -r module_name; do

  # Skip invalid entries
  [[ "$module_name" == ".." ]] && continue

  # Filter modules if specified
  if [[ -n "$FILTER_MODULES" && ",$FILTER_MODULES," != *",$module_name,"* ]]; then
    echo "⏭️ Skipping module $module_name (not in FILTER_MODULES)"
    continue
  fi

  echo "\n📦 Checking module: $module_name"

  # Fetch HTML for module version listing
  module_url="$AVM_INDEX_URL$module_name/"
  versions_html=$(curl -sSL "$module_url")

  echo "$versions_html" | grep -oE 'href="[^"]+/"' | \
    sed -E 's/href="([^"]+)\/"/\1/' | \
    sort | uniq | while read -r version; do

    # Filter versions if specified
    if [[ -n "$FILTER_VERSIONS" && ",$FILTER_VERSIONS," != *",$version,"* ]]; then
      echo "⏭️ Skipping version $version (not in FILTER_VERSIONS)"
      continue
    fi

    echo "🔄 Mirroring $module_name:$version"

    OCI_PATH="avm-$module_name/azurerm"

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

done

echo "\n✅ All done."
