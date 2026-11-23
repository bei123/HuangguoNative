#!/usr/bin/env bash
# 本地打未签名 Release IPA（供 AltStore / Sideloadly 等重签）
# 用法: ./scripts/build-unsigned-ipa.sh [version]
# 例:   ./scripts/build-unsigned-ipa.sh v1.2
set -euo pipefail
cd "$(dirname "$0")/.."
VER="${1:-v1.2}"
mkdir -p build/ipa
# 避免沿用旧 zip 里的残留文件
rm -f "build/ipa/HuangguoNative-${VER}-unsigned.ipa"
rm -rf build/Payload

xcodebuild \
  -project HuangguoNative.xcodeproj \
  -scheme HuangguoNative \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP=$(find build/DerivedData/Build/Products/Release-iphoneos -name '*.app' -maxdepth 1 | head -n 1)
test -n "$APP"
test -x "$APP/HuangguoNative"
if [[ -f "$APP/HuangguoNative.debug.dylib" ]]; then
  echo "ERROR: built a Debug package (found HuangguoNative.debug.dylib)" >&2
  exit 1
fi

mkdir -p build/Payload
cp -R "$APP" build/Payload/
( cd build && zip -qr "ipa/HuangguoNative-${VER}-unsigned.ipa" Payload )
rm -rf build/Payload
ls -lh "build/ipa/HuangguoNative-${VER}-unsigned.ipa"
echo "Upload: gh release upload ${VER} build/ipa/HuangguoNative-${VER}-unsigned.ipa --clobber"
