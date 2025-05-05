#!/bin/bash

set -euo pipefail

ACR_NAME="${ACR_NAME:-myacr.azurecr.io}"
FILTER_MODULES="${FILTER_MODULES:-}"       # Optional comma-separated list to mirror only specific modules
FILTER_VERSIONS="${FILTER_VERSIONS:-}"     # Optional comma-separated list to mirror only specific versions (only used if you override latest)

CSV_URLS=(
  "https://azure.github.io/Azure-Verified-Modules/module-indexes/TerraformResourceModules.csv"
  "https://azure.github.io/Azure-Verified-Modules/module-indexes/TerraformPatternModules.csv"
)

# Install required tools
command -v curl >/dev/null 2>&1 || { echo >&2 "curl is required but not installed. Exiting."; exit 1; }
command -v git >/dev/null 2>&1 || { echo >&2 "git is required but not installed. Exiting."; exit 1; }
command -v oras >/dev/null 2>&1 || { echo >&2 "oras is required but not installed. Exiting."; exit 1; }

mkdir -p temp_clone

for CSV_URL in "${CSV_URLS[@]}"; do
  echo "📥 Downloading module index CSV from $CSV_URL..."
  curl -sSL "$CSV_URL" -o avm_index.csv

  if [[ ! -s avm_index.csv ]]; then
    echo "❌ Failed to download or empty CSV at $CSV_URL"
    continue
  fi

  echo "📄 First few lines of the CSV:"
  head -n 5 avm_index.csv

  awk -F',' 'NR > 1 {
    gsub(/^"|"$/, "", $5); module_name=$5
    gsub(/^"|"$/, "", $7); status=$7
    gsub(/^"|"$/, "", $8); repo_url=$8
    gsub(/^"|"$/, "", $9); registry_url=$9
    if (status ~ /Available/ && repo_url ~ /^https:\/\/github.com/) {
      print module_name "," repo_url "," registry_url
    }
  }' avm_index.csv | sort | uniq | while IFS=',' read -r module_name repo_url registry_url; do

    echo "🧪 Found available module: $module_name"

    if [[ -n "$FILTER_MODULES" && ",${FILTER_MODULES}," != *",${module_name},"* ]]; then
      echo "⏭️ Skipping module $module_name (not in FILTER_MODULES)"
      continue
    fi

    module_path=$(echo "$registry_url" | sed -E 's#https://registry.terraform.io/modules/([^/]+)/([^/]+)/([^/]+).*#\1/\2/\3#')
    api_url="https://registry.terraform.io/v1/modules/$module_path"
    version=$(curl -s "$api_url" | jq -r '.tag')

    echo "📌 Extracted version: $version from $api_url"

    if [[ -z "$version" || "$version" == "null" ]]; then
      echo "⚠️ Could not extract version for $module_name — skipping"
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

    echo "🔍 Searching for .tf files..."
    CONTENT_DIR=$(find . -type f -name "*.tf" | head -n 1 | xargs dirname)

    if [[ -z "$CONTENT_DIR" ]]; then
      echo "⚠️ No Terraform files found in repo — skipping $module_name"
      cd ../.. && continue
    fi

    echo "📦 Packaging and pushing $module_name:$version from $CONTENT_DIR"

    OCI_PATH="$module_name/azurerm"
    az acr login --name "${ACR_NAME%%.azurecr.io}" || {
      echo "⚠️ Failed to login to ACR";
      cd ../.. && continue
    }

    readarray -t files < <(find "$CONTENT_DIR" -type f \( -name "*.tf" -o -name "*.md" \))
    if [[ ${#files[@]} -eq 0 ]]; then
      echo "⚠️ No files to push for $module_name"
      cd ../.. && continue
    fi

    echo "📂 Files to be pushed:"
    printf ' - %s\n' "${files[@]}"

    oras push "$ACR_NAME/$OCI_PATH:$version" \
      --artifact-type application/vnd.module.terraform \
      "${files[@]}" || {
        echo "⚠️ Failed to push $OCI_PATH:$version"; cd ../.. && continue;
      }

    echo "✅ Mirrored: $OCI_PATH:$version"

    cd ../..
    rm -rf "temp_clone/$module_name"
    popd >/dev/null

  done

  rm -f avm_index.csv
done

rm -rf temp_clone

echo -e "\n✅ All done."
