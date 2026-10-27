#!/usr/bin/env bash
# Deletes preinstalled toolchains that free the most space per second, so /nix
# and the Nix build directory (/nix/var/nix/builds) get it on /.
set -euo pipefail

if [[ -e /nix ]]; then
  echo "::error::/nix exists. Run nix-runner-space before installing Nix."
  exit 1
fi

before=$(df -B1 --output=avail / | tail -n 1)
pids=()
for path in /usr/share/swift /usr/local/.ghcup /usr/share/dotnet; do
  sudo rm -rf "${path}" &
  pids+=($!)
done
for pid in "${pids[@]}"; do wait "${pid}"; done
after=$(df -B1 --output=avail / | tail -n 1)
echo "Freed $(((after - before) >> 30)) GiB. / has $((after >> 30)) GiB free."
