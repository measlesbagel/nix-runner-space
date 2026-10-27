#!/usr/bin/env bash
# Usage: score.sh <dir>. Reads every sample.json under <dir>, writes
# <dir>/results.json and prints a Markdown report. Fails when a sample of this
# repo's action (variant "this" or "ref") is missing data or failed the gate.
set -euo pipefail

dir=$1
mapfile -t files < <(find "${dir}" -name sample.json | sort)
jq -s -f "$(dirname "$0")/score.jq" "${files[@]}" > "${dir}/results.json"

jq -r --argjson samples "${#files[@]}" '
  def f(x): if x == null then "-" else (x * 100 | round / 100 | tostring) end;
  def range(x): "\(f(x.med)) [\(f(x.min))–\(f(x.max))]";
  "Samples: \($samples). Failed or incomplete: \(.failed | length).",
  "",
  "u = -0.6 ln T + 0.4 ln S; score = u - u(baseline). Per arch, the baseline is the nbn-* variant with the highest u whose samples all passed the gate and whose median S beats the no-op'"'"'s. Its median S is the floor; a variant below it gets no score (-). [lo, hi] pairs worst and best samples.",
  "",
  "| arch | variant | n | gate ok | T s med [min–max] | S GiB med [min–max] | write MiB/s | score [lo, hi] | baseline (floor GiB) | images |",
  "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
  (.cells | sort_by(.arch, .variant)[] |
    "| \(.arch) | \(.variant) | \(.n) | \(.gate_ok) | \(range(.t)) | \(range(.s)) | \(f(.write_mibps.med)) | \(f(.score)) [\(f(.lo)), \(f(.hi))] | \(.baseline // "-") (\(f(.floor))) | \(.images | join(" ")) |"),
  "",
  "| variant | overall score [lo, hi] |",
  "| --- | --- |",
  (.overall | sort_by(-.score)[] | "| \(.variant) | \(f(.score)) [\(f(.lo)), \(f(.hi))] |"),
  "",
  (.failed[] | "FAILED \(.variant) \(.arch) #\(.n): t=\(.t) s=\(.s) gate=\(.gate | tojson)")
' "${dir}/results.json"

jq -e '[.failed[] | select(.variant == "this" or .variant == "ref")] | length == 0' "${dir}/results.json" > /dev/null
