#!/bin/bash

set -euo pipefail

AVM_INDEX_URL="https://azure.github.io/Azure-Verified-Modules/indexes/terraform/tf-resource-modules/index.json"
ACR_NAME="${ACR_NAME:-myacr.azurecr.io}"  # Default fallback if not passed as env var
FILTER_MODULES="${FILTER_MODULES:-}"       # Optional comma-separated list to mirror only specific modules
FILTER_VERSIONS="${FILTER_VERSIONS:-}"     # Optional comma-separated list to mirror only specific versions

# Install jq and oras if needed
command -v jq >/dev/null 2>&1 || { echo >&2 "jq is required but not installed. Exiting."; exit 1; }
command -v oras >/dev/null 2>&1 || { echo >&2 "oras is required but not installed. Exiting."; exit 1; }

# Fetch the index.json
echo "Fetching AVM Terraform index..."
curl -sSL "$AVM_INDEX_URL" -o index.json

# Loop through each module
jq -c '.modules[]' index.json | while read -r module; do
  NAME=$(echo "$module" | jq -r '.name')
  OCI_NAME=$(echo "$module" | jq -r '.oci.artifact')
  VERSIONS=$(echo "$module" | jq -r '.versions[]')

  # If filtering by modules
  if [[ -n "$FILTER_MODULES" && ",$FILTER_MODULES," != *",$NAME,"* ]]; then
    echo "⏭️ Skipping module $NAME (not in FILTER_MODULES)"
    continue
  fi

  echo "\n📦 Mirroring module: $NAME"

  for VERSION in $VERSIONS; do
    # If filtering by versions
    if [[ -n "$FILTER_VERSIONS" && ",$FILTER_VERSIONS," != *",$VERSION,"* ]]; then
      echo "⏭️ Skipping version $VERSION (not in FILTER_VERSIONS)"
      continue
    fi

    echo "🔄 Version: $VERSION"

    # Pull from GHCR
    oras pull "ghcr.io/azure/$OCI_NAME:$VERSION" -a || { echo "⚠️ Failed to pull $OCI_NAME:$VERSION"; continue; }

    # Push to ACR
    oras push "$ACR_NAME/$OCI_NAME:$VERSION" \
      --artifact-type application/vnd.module.terraform \
      ./*.tf ./*.md || { echo "⚠️ Failed to push $OCI_NAME:$VERSION"; continue; }

    echo "✅ Mirrored: $OCI_NAME:$VERSION"

    # Cleanup local files
    rm -f ./*.tf ./*.md
  done

done

echo "\n✅ All done."
