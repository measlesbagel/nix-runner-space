#!/usr/bin/env bash
# Usage: mark.sh <name>. Records the time and the free bytes under /nix in the
# sample, unscored, so other time and space definitions can be computed later.
set -euo pipefail
sample=${RUNNER_TEMP:?}/bench/sample.json
jq --arg name "$1" --arg t "$(date +%s.%N)" \
  --argjson nix "$(df -B1 --output=avail /nix | tail -n 1 | tr -d ' ')" \
  '.marks[$name] = {t: ($t | tonumber), nix_avail: $nix}' "${sample}" > "${sample}.new"
mv "${sample}.new" "${sample}"
