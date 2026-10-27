# nix-runner-space

Frees disk space for Nix on GitHub-hosted Ubuntu runners. It deletes the
preinstalled toolchains that free the most space per second of deletion, so
`/nix` and the Nix build directory (`/nix/var/nix/builds`) get the room on
`/`. On `ubuntu-latest` free space goes from about 88 GiB to about 118 GiB in
about 12 seconds. On `ubuntu-24.04-arm` it goes from about 107 GiB to about
119 GiB in about 3 seconds.

It is one composite step of bash in this repository. It uses no other action,
no network, no telemetry and no post step.

## Usage

Run it before Nix is installed. It fails if `/nix` already exists.

```yaml
steps:
  - uses: measlesbagel/nix-runner-space@909cfd352f66a83767a9acee790748eee9e64503
  - uses: DeterminateSystems/nix-installer-action@3138316df39ed29be04236d7ffc686fa525866aa # v23
  - run: nix build .#default
```

It has no inputs.

## What it deletes

The swapfile and Docker (the daemon and its images) stay. A path that an
image lacks is skipped. Everything else below is deleted, so these tools stop
working for the rest of the job:

| Path | Tool |
| --- | --- |
| `/usr/local/.ghcup` | GHC, Cabal and Stack from GHCup |
| `/usr/local/lib/android/sdk/ndk`, `build-tools`, `cmdline-tools`, `platforms/*/android.jar` | Android NDK and SDK |
| `/usr/share/dotnet`, `/home/runner/.dotnet`, `/etc/skel/.dotnet` | .NET runtimes, SDKs and global tools. On arm the SDKs stay, but .NET does not run without the runtimes. |
| `/usr/share/az_*` | Azure PowerShell modules |
| `/usr/share/swift` | Swift |
| `/usr/lib/jvm` | Java (every JDK) |
| `/home/packer` | Files left over from building the image |
| `/opt/microsoft` | Microsoft Edge and PowerShell 7, so `shell: pwsh` steps fail |
| `/usr/local/share/powershell` | PowerShell modules |
| `/usr/share/gradle-*` | Gradle |
| `/usr/local/share/chromium`, `/opt/google`, `/usr/lib/firefox` | Chromium, Chrome and Firefox |
| `/home/runner/.rustup`, `/etc/skel/.rustup` | Rust toolchains from rustup |
| `/opt/hostedtoolcache/copilot-cli` | GitHub Copilot CLI |
| `/opt/pipelinesagent-cache` | Azure Pipelines agent cache |
| `/usr/local/bin/{minikube,bicep,packer,stack,helm,azcopy,kustomize,kind}` | Those CLIs |

## Results

From bench run
[40568810501](https://github.com/measlesbagel/nix-runner-space/actions/runs/40568810501),
with 7 samples per variant and architecture. Each cell is the median with
the min–max range.

| | x86_64 (`ubuntu-latest`, Ubuntu 26.04) | arm64 (`ubuntu-24.04-arm`) |
| --- | --- | --- |
| Free space if nothing runs | 87.6 GiB | 106.8 GiB |
| nothing-but-nix v10, `cleave` in the foreground | 82.7 s [78.1–99.3], 114.5 GiB | 50.3 s [37.0–73.0], 114.9 GiB |
| nix-runner-space | 12.3 s [6.9–14.9], 117.6 GiB | 3.3 s [2.5–5.8], 118.7 GiB |
| Score | +1.15 [+1.00, +1.62] | +1.64 [+1.12, +2.04] |

The overall score is +1.40 [+1.06, +1.83]. nothing-but-nix's `cleave` in
the foreground was its best configuration on both architectures. Its
`rampage` mode failed every x86_64 sample (`apt-get` exit 100) and scored
below `cleave` on arm, and its background modes leave less free space than
doing nothing when the step returns.

Runner disks differ from host to host. In one run, the same code's x86_64
median was 9.6 s in one variant and 12.3 s in the other, so treat smaller
differences as noise.

## Write rate on nothing-but-nix's btrfs

nothing-but-nix puts `/nix` on btrfs over loop devices. A probe wrote all
free space under `/nix` with direct I/O and `fsync`, 3–4 samples per variant
and architecture, and found no write penalty against plain ext4 on the same
host. On x86_64 both wrote at about 392 MiB/s. On arm, btrfs was faster, at
about 321 MiB/s against 268–303 MiB/s. x86_64 hosts come in two classes that
write at about 390 or about 165–200 MiB/s, so compare write rates only on
the same host. The score does not count write rate.

## Benchmark

The `Bench` workflow measures each variant on fresh runners of both
architectures and runs the gate after it:

- `T`: wall time of the measured step, in seconds.
- `S`: free GiB on the filesystem that holds `/nix`, or on the one that holds
  the build directory if that has less, measured as the step returns. Space
  still being freed in the background does not count.
- The gate: `DeterminateSystems/nix-installer-action` installs Nix,
  `nix build nixpkgs#hello` builds, root writes `min(S - 4, 40)` GiB of random
  data into the daemon's build directory with `fsync` and deletes it, and
  `git` and `sudo` still work. A sample that fails any of these fails.

Each variant gets `u = -0.6 ln T + 0.4 ln S` from its medians. Per
architecture, the baseline is the nothing-but-nix v10 configuration with the
highest `u` among those that pass the gate in every sample and leave more
space than doing nothing. A variant scores `u - u_baseline`, and only if its
median `S` is at least the baseline's. The overall score is the mean of the
two architectures. Each score's range pairs the worst and best samples of
both sides.

The baseline runs as a local copy of nothing-but-nix's `action.yml` at
`687c797a730352432950c707ab493fcc951818d7`, with only its last step, `The
Post`, removed. That step calls `srz-zumix/post-run-action@v3` by tag, and
this repository allows only actions pinned to a commit SHA.
`bench/strip-post.sh` removes it and checks that nothing else was removed.

To run it:

```console
gh workflow run bench.yml \
  -f variants='["none","nbn-cleave-fg","this"]' \
  -f samples='[1,2,3,4,5]'
```

The variant `ref` runs another commit of this repository (`-f ref=<sha>`), to
compare a change with the version before it. The score table is in the run
summary and in the `results` artifact.
