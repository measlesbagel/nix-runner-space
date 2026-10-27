#!/usr/bin/env bash
# Deletes preinstalled toolchains that free the most space per second, so /nix
# and the Nix build directory (/nix/var/nix/builds) get it on /. Swap and
# Docker stay.
set -euo pipefail
shopt -s nullglob

if [[ -e /nix ]]; then
  echo "::error::/nix exists. Run nix-runner-space before installing Nix."
  exit 1
fi

# arm has room to keep the .NET SDK, whose 47k inodes are the slowest space
# on the list. x64 needs that space.
if [[ "$(uname -m)" == aarch64 ]]; then
  dotnet=(/usr/share/dotnet/shared /usr/share/dotnet/packs)
else
  dotnet=(/usr/share/dotnet)
fi

# Ordered by space freed per inode, since deletion time follows inode count.
# Paths an image lacks are skipped.
targets=(
  /usr/local/bin/{minikube,bicep,packer,stack,helm,azcopy,kustomize,kind}
  /usr/local/lib/android/sdk/platforms/*/android.jar
  /opt/hostedtoolcache/copilot-cli
  /opt/pipelinesagent-cache
  /home/runner/.rustup
  /etc/skel/.rustup
  /opt/google
  /usr/local/share/powershell
  /opt/microsoft
  /usr/share/swift
  /usr/local/share/chromium
  /usr/lib/firefox
  /usr/lib/jvm
  /home/packer
  /home/runner/.dotnet
  /etc/skel/.dotnet
  /usr/local/lib/android/sdk/build-tools
  /usr/local/lib/android/sdk/cmdline-tools
  /usr/local/.ghcup
  /usr/local/lib/android/sdk/ndk
  /usr/share/gradle-*
  /usr/share/az_*
  "${dotnet[@]}"
)

before=$(df -B1 --output=avail / | tail -n 1)
paths=()
for path in "${targets[@]}"; do
  if [[ -e "${path}" ]]; then paths+=("${path}"); fi
done
# Cold deletion waits on disk reads of directories and inodes, so many rm
# processes at once keep more reads in flight.
sudo find "${paths[@]}" -mindepth 3 -maxdepth 3 -print0 |
  sudo xargs -0 -r -P 32 -n 16 rm -rf
sudo rm -rf "${paths[@]}"
after=$(df -B1 --output=avail / | tail -n 1)
echo "Freed $(((after - before) >> 30)) GiB. / has $((after >> 30)) GiB free."
