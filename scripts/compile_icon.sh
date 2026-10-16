#!/bin/zsh
# Regenerate the distributable macOS icon asset from our editable .icon source.
set -euo pipefail
cd "${0:A:h:h}"
compiler="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}/usr/bin/actool"
if [[ ! -x "$compiler" ]]; then
  compiler=$(xcrun --find actool 2>/dev/null) || { print -u2 'Icon compilation requires full Xcode (actool).'; exit 1; }
fi
stage=$(mktemp -d "${TMPDIR:-/tmp}/dotmi-icon-compile.XXXXXX")
trap 'rm -rf "$stage"' EXIT
# Keep compiler input outside synced folders, and never alter installed app icons.
cp -R Resources/AppIcon.icon "$stage/AppIcon.icon"
mkdir "$stage/output"
"$compiler" "$stage/AppIcon.icon" \
  --compile "$stage/output" \
  --app-icon AppIcon --include-all-app-icons \
  --platform macosx --target-device mac \
  --minimum-deployment-target 13.0 \
  --bundle-identifier local.tokit.xunji \
  --output-partial-info-plist "$stage/icon-info.plist" \
  --output-format human-readable-text --warnings --errors
[[ -s "$stage/output/Assets.car" ]] || { print -u2 'Icon compiler did not produce Assets.car'; exit 1; }
cp "$stage/output/Assets.car" Resources/Assets.car
print 'Updated Resources/Assets.car. Legacy AppIcon.icns remains the fallback for older macOS.'
