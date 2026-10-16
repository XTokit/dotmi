#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
source scripts/common.sh
install_app=false
output="${TMPDIR:-/tmp}/xunji-artifacts/点觅.app"
while (( $# )); do
  case "$1" in
    --install) install_app=true; shift ;;
    --output) [[ $# -ge 2 ]] || exit 2; output="$2"; shift 2 ;;
    --help) print 'Usage: ./build.sh [--install] [--output /path/点觅.app]'; print 'Default: build only; --install updates /Applications/点觅.app.'; exit 0 ;;
    *) print -u2 "Unknown option: $1"; exit 2 ;;
  esac
done
[[ "${output:t}" == '点觅.app' ]] || { print -u2 'The application bundle must be named 点觅.app'; exit 2; }
[[ "${output:A}" != /Applications/* ]] || { print -u2 'Use --install to update /Applications/点觅.app'; exit 2; }
swift build "${swift_flags[@]}" -c release --product Xunji
bin_dir=$(swift build "${swift_flags[@]}" -c release --show-bin-path)
package_dir=$(mktemp -d "${TMPDIR:-/tmp}/xunji-package.XXXXXX")
trap 'rm -rf "$package_dir"' EXIT
app="$package_dir/点觅.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/Xunji" "$app/Contents/MacOS/Xunji"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp Resources/Assets.car "$app/Contents/Resources/Assets.car"
cp Resources/MenuBarTemplate.png "$app/Contents/Resources/MenuBarTemplate.png"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
if $install_app; then
  python3 install.py "$app"
else
  # Copy the verified bundle only; never register or launch it automatically.
  python3 - "$app" "$output" <<'PY'
import shutil, sys
from pathlib import Path
source, target = map(Path, sys.argv[1:])
target = target.expanduser().absolute()
if target.is_symlink():
    raise SystemExit('Refusing to replace a symbolic link')
if target.exists():
    import plistlib
    with (target / 'Contents/Info.plist').open('rb') as f:
        if plistlib.load(f).get('CFBundleIdentifier') != 'local.tokit.xunji':
            raise SystemExit('Output belongs to a different app')
    shutil.rmtree(target)
target.parent.mkdir(parents=True, exist_ok=True)
shutil.copytree(source, target, symlinks=True)
print('Built (not installed):', target)
PY
fi
