#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source scripts/common.sh
swift run "${swift_flags[@]}" -c release SearchChecks
if [[ "${1:-}" == --integration ]]; then
  swift build "${swift_flags[@]}" -c release --product Xunji
  export XUNJI_TEST_BINARY="$(swift build "${swift_flags[@]}" -c release --show-bin-path)/Xunji"
  python3 Tests/verify_locations.py
  python3 Tests/verify_incremental.py
  python3 Tests/verify_preview.py
  python3 Tests/verify_interaction.py
fi
