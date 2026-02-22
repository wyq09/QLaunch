#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXECUTABLE_SOURCE_NAME="QLaunch"
APP_DISPLAY_NAME="QLaunch"
BUNDLE_ID="com.local.qlaunch"
APP_NAME="${APP_DISPLAY_NAME}.app"
APP_EXECUTABLE_NAME="${APP_DISPLAY_NAME}"
ICON_BASENAME="AppIcon"
ICNS_FILENAME="${ICON_BASENAME}.icns"

BUILD_DIR="${ROOT_DIR}/.build/arm64-apple-macosx/release"
DIST_DIR="${ROOT_DIR}/dist"
APP_DIR="${DIST_DIR}/${APP_NAME}"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
PLIST_PATH="${CONTENTS_DIR}/Info.plist"
BIN_PATH="${BUILD_DIR}/${EXECUTABLE_SOURCE_NAME}"
ZIP_PATH="${DIST_DIR}/${APP_NAME}.zip"
ICON_DIR="${ROOT_DIR}/AppIcons"

create_icns_from_png() {
  local source_png="$1"
  local output_icns="$2"

  local iconset_dir
  iconset_dir="$(mktemp -d /tmp/qlaunch-iconset.XXXXXX)/${ICON_BASENAME}.iconset"
  mkdir -p "${iconset_dir}"

  sips -z 16 16 "${source_png}" --out "${iconset_dir}/icon_16x16.png" >/dev/null
  sips -z 32 32 "${source_png}" --out "${iconset_dir}/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "${source_png}" --out "${iconset_dir}/icon_32x32.png" >/dev/null
  sips -z 64 64 "${source_png}" --out "${iconset_dir}/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "${source_png}" --out "${iconset_dir}/icon_128x128.png" >/dev/null
  sips -z 256 256 "${source_png}" --out "${iconset_dir}/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "${source_png}" --out "${iconset_dir}/icon_256x256.png" >/dev/null
  sips -z 512 512 "${source_png}" --out "${iconset_dir}/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "${source_png}" --out "${iconset_dir}/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "${source_png}" --out "${iconset_dir}/icon_512x512@2x.png" >/dev/null

  iconutil -c icns "${iconset_dir}" -o "${output_icns}"
  rm -rf "$(dirname "${iconset_dir}")"
}

install_app_icon() {
  local icon_icns_path="${RESOURCES_DIR}/${ICNS_FILENAME}"

  if [[ -f "${ICON_DIR}/${ICNS_FILENAME}" ]]; then
    cp "${ICON_DIR}/${ICNS_FILENAME}" "${icon_icns_path}"
    return
  fi

  local source_png=""
  if [[ -f "${ICON_DIR}/appstore.png" ]]; then
    source_png="${ICON_DIR}/appstore.png"
  else
    source_png="$(find "${ICON_DIR}" -maxdepth 2 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) | head -n 1 || true)"
  fi

  if [[ -z "${source_png}" ]]; then
    echo "warning: no icon found in ${ICON_DIR}; app will use default icon" >&2
    return
  fi

  create_icns_from_png "${source_png}" "${icon_icns_path}"
}

cd "${ROOT_DIR}"

swift build -c release

if [[ ! -x "${BIN_PATH}" ]]; then
  echo "error: release binary not found at ${BIN_PATH}" >&2
  exit 1
fi

rm -rf "${APP_DIR}" "${ZIP_PATH}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BIN_PATH}" "${MACOS_DIR}/${APP_EXECUTABLE_NAME}"
chmod 755 "${MACOS_DIR}/${APP_EXECUTABLE_NAME}"

install_app_icon

cat > "${PLIST_PATH}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>${APP_EXECUTABLE_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_DISPLAY_NAME}</string>
  <key>CFBundleName</key>
  <string>${APP_DISPLAY_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleIconFile</key>
  <string>${ICON_BASENAME}</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

plutil -lint "${PLIST_PATH}" >/dev/null
codesign --force --deep --sign - "${APP_DIR}"
codesign --verify --deep --strict "${APP_DIR}"

ditto -c -k --sequesterRsrc --keepParent "${APP_DIR}" "${ZIP_PATH}"

printf "Packed app: %s\n" "${APP_DIR}"
printf "Packed zip: %s\n" "${ZIP_PATH}"
