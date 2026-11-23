#!/bin/bash
# 双击或在 Terminal 运行：打未签名 Release IPA 并上传到 GitHub Release
# 用法: ./scripts/build-and-upload-release-ipa.command [version]
# 例:   ./scripts/build-and-upload-release-ipa.command v1.2
set -euo pipefail
cd "$(dirname "$0")/.."
VER="${1:-v1.2}"

# 若本机已开 HTTP 代理（常见 7890），自动带上；否则直连
if [[ -z "${https_proxy:-}${HTTPS_PROXY:-}" ]]; then
  if nc -z 127.0.0.1 7890 2>/dev/null; then
    export https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890
    export HTTPS_PROXY=http://127.0.0.1:7890 HTTP_PROXY=http://127.0.0.1:7890
  fi
fi

echo "==> Release unsigned IPA → GitHub Release ${VER}"
rm -f build/ipa/.done build/ipa/.failed
mkdir -p build/ipa

if ./scripts/build-unsigned-ipa.sh "$VER"; then
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  unzip -q "build/ipa/HuangguoNative-${VER}-unsigned.ipa" -d "$TMP"
  if [[ -f "$TMP/Payload/HuangguoNative.app/HuangguoNative.debug.dylib" ]]; then
    echo "ERROR: still a Debug package" | tee build/ipa/.failed
    exit 1
  fi
  ls -lh "build/ipa/HuangguoNative-${VER}-unsigned.ipa"
  if ! gh release view "$VER" >/dev/null 2>&1; then
    gh release create "$VER" --title "$VER" --generate-notes --target main
  fi
  gh release upload "$VER" "build/ipa/HuangguoNative-${VER}-unsigned.ipa" --clobber
  touch build/ipa/.done
  echo DONE
  afplay /System/Library/Sounds/Glass.aiff 2>/dev/null || true
else
  echo FAIL | tee build/ipa/.failed
  exit 1
fi
