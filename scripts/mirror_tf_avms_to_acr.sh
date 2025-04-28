#!/bin/bash

set -euo pipefail

AVM_INDEX_URL="https://azure.github.io/Azure-Verified-Modules/indexes/terraform/tf-resource-modules/"
ACR_NAME="${ACR_NAME:-myacr.azurecr.io}"
FILTER_MODULES="${FILTER_MODULES:-}"       # Optional comma-separated list to mirror only specific modules
FILTER_VERSIONS="${FILTER_VERSIONS:-}"     # Optional comma-separated list to mirror only specific versions

# Install required tools
command -v jq >/dev/null 2>&1 || { echo >&2 "jq is required but not installed. Exiting."; exit 1; }
command -v curl >/dev/null 2>&1 || { echo >&2 "curl is required but not installed. Exiting."; exit 1; }
command -v oras >/dev/null 2>&1 || { echo >&2 "oras is required but not installed. Exiting."; exit 1; }

# Fetch the module list HTML
echo "Fetching AVM Terraform module list..."
HTML_CONTENT=$(curl -sSL "$AVM_INDEX_URL")

if [[ -z "$HTML_CONTENT" ]]; then
  echo "❌ Failed to fetch module index from $AVM_INDEX_URL"
  exit 1
fi

# Extract modules using awk (safe across environments)
MODULE_NAMES=$(echo "$HTML_CONTENT" | awk -F 'href="' '/href/ {split($2,a,"/"); print a[1]}' | grep -v '^\.\.$' | sort | uniq)

if [[ -z "$MODULE_NAMES" ]]; then
  echo "❌ No module names found in index HTML. Check parsing logic or page structure."
  exit 1
fi

echo "$MODULE_NAMES" | while read -r module_name; do

  # Filter modules if specified
  if [[ -n "$FILTER_MODULES" && ",$FILTER_MODULES," != *",$module_name,"* ]]; then
    echo "⏭️ Skipping module $module_name (not in FILTER_MODULES)"
    continue
  fi

  echo "\n📦 Checking module: $module_name"

  # Fetch HTML for module version listing
  module_url="$AVM_INDEX_URL$module_name/"
  versions_html=$(curl -sSL "$module_url")

  version_names=$(echo "$versions_html" | awk -F 'href="' '/href/ {split($2,a,"/"); print a[1]}' | grep -v '^\.\.$' | sort | uniq)

  if [[ -z "$version_names" ]]; then
    echo "⚠️ No versions found for $module_name"
    continue
  fi

  echo "$version_names" | while read -r version; do

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
