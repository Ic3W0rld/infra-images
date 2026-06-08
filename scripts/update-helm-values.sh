#!/usr/bin/env bash
# update-helm-values.sh
#
# Reads mirrors.lock.yaml and patches Helm values files in the infra repo
# so every upstream image reference points to its GHCR mirror.
#
# Usage:
#   ./scripts/update-helm-values.sh <infra-repo-path>
#
# Example:
#   ./scripts/update-helm-values.sh ~/git
#
# Prerequisites: yq ≥ 4, sed, git

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK_FILE="${SCRIPT_DIR}/../mirrors.lock.yaml"
INFRA_DIR="${1:?Usage: $0 <infra-repo-path>}"

if [[ ! -f "$LOCK_FILE" ]]; then
  echo "Error: $LOCK_FILE not found. Run the mirror workflow first." >&2
  exit 1
fi

if [[ ! -d "$INFRA_DIR/CTRL_SHIFT" ]]; then
  echo "Error: $INFRA_DIR does not look like the infra repo (no CTRL_SHIFT/ dir)." >&2
  exit 1
fi

GHCR="ghcr.io"
OWNER="ic3w0rld"

echo "Patching values files in $INFRA_DIR ..."
echo ""

changed=0

apply_patch() {
  local file="$1"
  local old_repo="$2"
  local new_repo="$3"
  local old_tag="$4"
  local new_tag="$5"

  if [[ ! -f "$file" ]]; then return; fi

  # Match lines with the upstream repository value and replace
  if grep -qF "$old_repo" "$file" 2>/dev/null; then
    sed -i "s|${old_repo}|${new_repo}|g" "$file"
    echo "  repo : $old_repo → $new_repo"
    changed=$((changed + 1))
  fi

  # Replace the tag if the upstream tag appears literally
  if [[ -n "$old_tag" && "$old_tag" != "latest" ]] && grep -qF "$old_tag" "$file" 2>/dev/null; then
    sed -i "s|${old_tag}|${new_tag}|g" "$file"
    echo "  tag  : $old_tag → $new_tag"
  fi
}

# Iterate every entry in the lock file
count=$(yq '.images | length' "$LOCK_FILE")

for (( i=0; i<count; i++ )); do
  name=$(yq ".images[$i].name" "$LOCK_FILE")
  source=$(yq ".images[$i].source" "$LOCK_FILE")
  upstream_tag=$(yq ".images[$i].upstream_tag" "$LOCK_FILE")
  resolved_tag=$(yq ".images[$i].resolved_tag" "$LOCK_FILE")
  ghcr_repo="${GHCR}/${OWNER}/${name}"

  # Strip registry prefix from source for matching plain repository: lines
  bare_repo="${source#registry-1.docker.io/}"
  bare_repo="${bare_repo#docker.io/}"

  # Collect all values files to patch
  while IFS= read -r vf; do
    echo "[$name] $vf"
    apply_patch "$vf" "$source"    "$ghcr_repo" "$upstream_tag" "$resolved_tag"
    apply_patch "$vf" "$bare_repo" "$ghcr_repo" "$upstream_tag" "$resolved_tag"
  done < <(find "$INFRA_DIR/CTRL_SHIFT" \
    -path "*/values/prod/values-*prod*.yaml" \
    -type f)

done

echo ""
echo "Done. $changed replacements made."
echo "Review with: git -C $INFRA_DIR diff CTRL_SHIFT/"
