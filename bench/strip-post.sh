#!/usr/bin/env bash
# Usage: strip-post.sh <action.yml>. Deletes the final "The Post" step from
# nothing-but-nix's action, the only step that uses another action
# (srz-zumix/post-run-action@v3, not SHA-pinned, so this repo cannot run it).
# Fails unless exactly that step went and no other uses: remains.
set -euo pipefail
action=$1
before=$(wc -l < "${action}")
removed=$(sed -n '/^    - name: The Post$/,$p' "${action}")
grep -q 'uses: srz-zumix/post-run-action@v3' <<< "${removed}"
sed -i '/^    - name: The Post$/,$d' "${action}"
if grep -n 'uses:' "${action}"; then exit 1; fi
echo "removed $((before - $(wc -l < "${action}"))) of ${before} lines:"
echo "${removed}"
