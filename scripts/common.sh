#!/bin/zsh
# Shared, platform-native SwiftPM settings. No dependency downloads are required.
project_root="${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/xunji-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/xunji-swift-cache"
build_dir="${XUNJI_BUILD_DIR:-${TMPDIR:-/tmp}/xunji-build}"
build_arch="${XUNJI_ARCH:-$(uname -m)}"
case "$build_arch" in arm64|x86_64) ;; *) print -u2 'Supported architectures: arm64, x86_64'; exit 2 ;; esac
swift_flags=(--scratch-path "$build_dir" --cache-path "${TMPDIR:-/tmp}/xunji-spm-cache" --config-path "${TMPDIR:-/tmp}/xunji-spm-config" --security-path "${TMPDIR:-/tmp}/xunji-spm-security" --disable-sandbox --arch "$build_arch")
