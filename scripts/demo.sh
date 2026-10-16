#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source scripts/common.sh
swift build "${swift_flags[@]}" -c release --product Xunji
bin_dir=$(swift build "${swift_flags[@]}" -c release --show-bin-path)
demo_dir=$(mktemp -d "${TMPDIR:-/tmp}/xunji-demo.XXXXXX")
trap 'rm -rf "$demo_dir"' EXIT
XUNJI_DEMO=1 XUNJI_DATA_DIR="$demo_dir" "$bin_dir/Xunji"
