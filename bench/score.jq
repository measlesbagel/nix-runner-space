# Input: every sample.json of one run (jq -s). Output: per-cell medians, the
# baseline and scores. A variant's utility is u = -0.6 ln T + 0.4 ln S, so its
# score against a baseline is u - u_b. Per arch, the baseline is the nbn-*
# variant with the highest u among those that passed the gate in every sample
# and whose median S is above the no-op's ("none"). Its median S is the floor:
# a variant below it gets no score. lo and hi pair each side's worst and best
# samples.
def median: sort | if length == 0 then null elif length % 2 == 1 then .[length / 2 | floor] else (.[length / 2 - 1] + .[length / 2]) / 2 end;
def stat(f): map(f | select(. != null)) | {med: median, min: min, max: max};
def u: -0.6 * (.t.med | log) + 0.4 * (.s.med | log);

(map(select(.t == null or .s == null or .gate.ok != true)) | map({variant, arch, n, image, t, s, gate})) as $failed
| group_by([.arch, .variant])
| map({
    arch: .[0].arch,
    variant: .[0].variant,
    n: length,
    gate_ok: (map(select(.gate.ok == true)) | length),
    images: (map(.image) | unique),
    t: stat(if .s == null then null else .t end),
    s: stat(.s),
    write_mibps: stat(.gate.write_mibps)
  } | . + {u: (if .s.med == null then null else u end)})
| group_by(.arch)
| map(
    (map(select(.variant == "none"))[0].s.med) as $none
    | (if $none == null then null else
        map(select((.variant | startswith("nbn-")) and .gate_ok == .n and .u != null and .s.med > $none)) | max_by(.u)
      end) as $b
    | map(. + {baseline: $b.variant, floor: $b.s.med}
        + if $b == null or .u == null or .s.med < $b.s.med then {} else {
          score: (.u - $b.u),
          lo: (0.6 * (($b.t.min / .t.max) | log) + 0.4 * ((.s.min / $b.s.max) | log)),
          hi: (0.6 * (($b.t.max / .t.min) | log) + 0.4 * ((.s.max / $b.s.min) | log))
        } end)
  )
| flatten as $cells
| ($cells | map(.arch) | unique | length) as $arches
| {
    cells: $cells,
    overall: ($cells | map(select(.score != null)) | group_by(.variant)
      | map(select(length == $arches) | {
          variant: .[0].variant,
          score: (map(.score) | add / length),
          lo: (map(.lo) | add / length),
          hi: (map(.hi) | add / length)
        })),
    failed: $failed
  }
