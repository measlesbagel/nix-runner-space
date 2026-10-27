#!/usr/bin/env bash
# Gate checks 3 and 4, after Nix is installed and has built hello. Finds the
# directory the daemon builds in, sets S to the smaller of /nix and that
# directory at measure time, writes min(S - 4, 40) GiB of incompressible data
# there as root, deletes it, then checks git and sudo.
set -euo pipefail
sample=${RUNNER_TEMP:?}/bench/sample.json

# --keep-failed makes the daemon print the build directory it used.
# shellcheck disable=SC2016 # the ${...} is Nix interpolation
kept=$(nix build --no-link --keep-failed --impure --expr \
  'derivation { name = "bench-build-dir-${toString builtins.currentTime}"; system = builtins.currentSystem; builder = "/bin/sh"; args = [ "-c" "exit 1" ]; }' \
  2>&1 | sed -n 's/^note: keeping build directory "\(.*\)"$/\1/p' || true)
[[ -n "${kept}" ]] || { echo "could not find the build directory"; exit 1; }
sudo rm -rf "$(dirname "${kept}")"
build_root=$(dirname "$(dirname "${kept}")")
echo "build directory: ${build_root}"

jq --arg b "${build_root}" '
  def gib: . / 1073741824;
  (.avail | to_entries | map(select(.key as $k | $b == $k or ($b | startswith($k + "/")))) | max_by(.key | length).value) as $build
  | .build_dir = $b
  | .s_nix = (.avail["/nix"] | gib)
  | .s_build = ($build | gib)
  | .s = ([.s_nix, .s_build] | min)
' "${sample}" > "${sample}.new"
mv "${sample}.new" "${sample}"
jq -e '.s_build != null' "${sample}" > /dev/null || { echo "no measurement covers ${build_root}"; exit 1; }

size_mib=$(jq '[(.s - 4) * 1024, 40 * 1024] | min | floor' "${sample}")
chunk_mib=256
count=$((size_mib / chunk_mib))
((count > 0)) || { echo "S - 4 is below ${chunk_mib} MiB"; exit 1; }
head -c "${chunk_mib}M" /dev/urandom > /dev/shm/bench-chunk
file=${build_root}/bench-gate.bin
start=$(date +%s.%N)
for ((i = 0; i < count; i++)); do cat /dev/shm/bench-chunk; done |
  sudo dd of="${file}" bs=16M iflag=fullblock oflag=direct conv=fsync status=none
end=$(date +%s.%N)
written=$(sudo stat -c %s "${file}")
sudo rm -f "${file}" /dev/shm/bench-chunk
((written == count * chunk_mib * 1048576)) || { echo "wrote ${written} bytes, wanted $((count * chunk_mib)) MiB"; exit 1; }
echo "wrote and deleted $((count * chunk_mib)) MiB under ${build_root}"

git -C "${GITHUB_WORKSPACE:?}" rev-parse HEAD
sudo -n true

jq --argjson mib "$((count * chunk_mib))" --arg start "${start}" --arg end "${end}" '
  .gate.write_mib = $mib
  | .gate.write_mibps = ($mib / (($end | tonumber) - ($start | tonumber)))
' "${sample}" > "${sample}.new"
mv "${sample}.new" "${sample}"
