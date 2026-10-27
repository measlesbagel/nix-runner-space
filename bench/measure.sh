#!/usr/bin/env bash
# Runs as the step right after the measured one. T is the time since the step
# before it wrote BENCH_T0. S comes from df at this moment, for /nix and for
# each place the Nix build directory can be; gate.sh picks the one Nix uses.
set -euo pipefail
t1=$(date +%s.%N)

avail() {
  local p=$1
  until [[ -e "${p}" ]]; do p=$(dirname "${p}"); done
  df -B1 --output=avail "${p}" | tail -n 1 | tr -d ' '
}

mkdir -p "${RUNNER_TEMP:?}/bench"
jq -n \
  --arg variant "${VARIANT:?}" --arg arch "${ARCH:?}" --argjson n "${SAMPLE:?}" \
  --arg image "${ImageOS:-}/${ImageVersion:-}" \
  --arg t0 "${BENCH_T0:?}" --arg t1 "${t1}" \
  --argjson nix "$(avail /nix)" --argjson builds "$(avail /nix/var/nix/builds)" --argjson tmp "$(avail /tmp)" \
  '{variant: $variant, arch: $arch, n: $n, image: $image,
    t0: ($t0 | tonumber), t1: ($t1 | tonumber),
    t: (($t1 | tonumber) - ($t0 | tonumber)),
    avail: {"/nix": $nix, "/nix/var/nix/builds": $builds, "/tmp": $tmp}}' \
  > "${RUNNER_TEMP}/bench/sample.json"
cat "${RUNNER_TEMP}/bench/sample.json"
df -hT
findmnt -T /nix || true
