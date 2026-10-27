#!/usr/bin/env bash
# Deletes preinstalled toolchains that free the most space per second, so /nix
# and the Nix build directory (/nix/var/nix/builds) get it on /.
set -euo pipefail

if [[ -e /nix ]]; then
  echo "::error::/nix exists. Run nix-runner-space before installing Nix."
  exit 1
fi

before=$(df -B1 --output=avail / | tail -n 1)
paths=()
for path in /usr/share/swift /usr/local/.ghcup /usr/share/dotnet; do
  if [[ -e "${path}" ]]; then paths+=("${path}"); fi
done
# Cold deletion waits on disk reads of directories and inodes, so many rm
# processes at once keep more reads in flight.
sudo find "${paths[@]}" -mindepth 3 -maxdepth 3 -print0 |
  sudo xargs -0 -r -P 32 -n 16 rm -rf
sudo rm -rf "${paths[@]}"
after=$(df -B1 --output=avail / | tail -n 1)
echo "Freed $(((after - before) >> 30)) GiB. / has $((after >> 30)) GiB free."
