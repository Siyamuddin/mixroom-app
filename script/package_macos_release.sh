#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Mixroom"
APP_BUNDLE="$ROOT_DIR/build/macos/Build/Products/Release/$APP_NAME.app"
DIST_DIR="$ROOT_DIR/build/distribution"
ENTITLEMENTS_SRC="$ROOT_DIR/macos/Runner/Release.entitlements"
GENERATED_ENTITLEMENTS="$ROOT_DIR/build/macos/Build/Intermediates.noindex/Runner.build/Release/Runner.build/$APP_NAME.app.xcent"
TEAM_ID="${MACOS_TEAM_ID:-X8Y4B4222A}"
BUNDLE_ID="${MACOS_BUNDLE_ID:-com.mixroom.mixroomapp}"
SIGN_IDENTITY="${MACOS_CODESIGN_IDENTITY:-}"
NOTARY_PROFILE="${MACOS_NOTARY_KEYCHAIN_PROFILE:-}"
DMG_PATH="${MACOS_DMG_PATH:-$DIST_DIR/$APP_NAME-macOS.dmg}"
DMG_VOLUME_NAME="${MACOS_DMG_VOLUME_NAME:-$APP_NAME Installer}"
SKIP_NOTARIZATION="${MACOS_SKIP_NOTARIZATION:-0}"
SKIP_BUILD="${MACOS_SKIP_BUILD:-0}"

usage() {
  cat >&2 <<EOF
usage: $0 [flutter build macos args...]

Required for distributable builds:
  MACOS_CODESIGN_IDENTITY          Developer ID Application identity name.
                                  If omitted, the first installed Developer ID Application identity is used.
  MACOS_NOTARY_KEYCHAIN_PROFILE    notarytool keychain profile name.
                                  Required unless MACOS_SKIP_NOTARIZATION=1.

Optional:
  MACOS_TEAM_ID                    Apple Developer Team ID. Defaults to X8Y4B4222A.
  MACOS_DMG_PATH                   Output DMG path. Defaults to build/distribution/Mixroom-macOS.dmg.
  MACOS_DMG_VOLUME_NAME            Mounted DMG volume name. Defaults to "Mixroom Installer".
  MACOS_SKIP_NOTARIZATION=1        Build a signed-but-not-notarized DMG for local testing only.
  MACOS_SKIP_BUILD=1               Re-sign/package the existing Release app without rebuilding it.
  MACOS_KEEP_RESTRICTED_ENTITLEMENTS=1
                                  Keep profile-gated entitlements for diagnostic builds.
  MACOS_STRIP_KEYCHAIN_ACCESS_GROUPS=1
                                  Strip keychain access groups for diagnostic builds.
EOF
}

fail() {
  echo "error: $*" >&2
  exit 1
}

find_developer_id_identity() {
  /usr/bin/security find-identity -p codesigning -v \
    | /usr/bin/awk -F '"' '/Developer ID Application/ { print $2; exit }'
}

require_tools() {
  command -v flutter >/dev/null || fail "flutter is not installed or not on PATH."
  command -v xcrun >/dev/null || fail "xcrun is not installed or not on PATH."
  command -v codesign >/dev/null || fail "codesign is not installed or not on PATH."
  command -v hdiutil >/dev/null || fail "hdiutil is not installed or not on PATH."
}

prepare_identity() {
  if [[ -z "$SIGN_IDENTITY" ]]; then
    SIGN_IDENTITY="$(find_developer_id_identity)"
  fi

  [[ -n "$SIGN_IDENTITY" ]] || fail "No Developer ID Application signing identity found. Install the certificate or set MACOS_CODESIGN_IDENTITY."

  if [[ "$SKIP_NOTARIZATION" != "1" && -z "$NOTARY_PROFILE" ]]; then
    fail "MACOS_NOTARY_KEYCHAIN_PROFILE is required for employee/customer DMG distribution."
  fi
}

expanded_entitlements_path() {
  local entitlements_path="$DIST_DIR/Release.expanded.entitlements"
  /bin/mkdir -p "$DIST_DIR"

  /usr/bin/sed 's|$(AppIdentifierPrefix)|'"$TEAM_ID"'.|g' "$ENTITLEMENTS_SRC" > "$entitlements_path"
  /usr/bin/sed -i '' 's|$(CFBundleIdentifier)|'"$BUNDLE_ID"'|g' "$entitlements_path"
  /usr/bin/sed -i '' 's|$(TeamIdentifier)|'"$TEAM_ID"'|g' "$entitlements_path"

  /usr/libexec/PlistBuddy -c "Delete :com.apple.security.get-task-allow" "$entitlements_path" >/dev/null 2>&1 || true

  if [[ "${MACOS_KEEP_RESTRICTED_ENTITLEMENTS:-0}" != "1" ]]; then
    /usr/libexec/PlistBuddy -c "Delete :com.apple.developer.applesignin" "$entitlements_path" >/dev/null 2>&1 || true
  fi

  if [[ "${MACOS_STRIP_KEYCHAIN_ACCESS_GROUPS:-0}" == "1" ]]; then
    /usr/libexec/PlistBuddy -c "Delete :keychain-access-groups" "$entitlements_path" >/dev/null 2>&1 || true
  fi

  /usr/bin/plutil -convert xml1 "$entitlements_path"
  /usr/bin/plutil -lint "$entitlements_path" >/dev/null
  echo "$entitlements_path"
}

sign_path() {
  local path="$1"
  /usr/bin/codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$path"
}

find_macho_files() {
  local root="$1"

  /usr/bin/find "$root" -type f -print0 | while IFS= read -r -d '' path; do
    if /usr/bin/file "$path" | /usr/bin/grep -q "Mach-O"; then
      /bin/echo "$path"
    fi
  done
}

homebrew_dependencies_for() {
  local binary="$1"
  /usr/bin/otool -L "$binary" \
    | /usr/bin/awk '/\/opt\/homebrew\// { print $1 }'
}

embed_homebrew_dylibs() {
  local dylib_dir="$APP_BUNDLE/Contents/Frameworks/Homebrew"
  local copied=1

  /bin/mkdir -p "$dylib_dir"

  while [[ "$copied" == "1" ]]; do
    copied=0

    while IFS= read -r dep; do
      local basename
      basename="$(/usr/bin/basename "$dep")"

      [[ -f "$dep" ]] || fail "Homebrew dylib dependency not found: $dep"

      if [[ ! -f "$dylib_dir/$basename" ]]; then
        /bin/cp -L "$dep" "$dylib_dir/$basename"
        /bin/chmod u+w "$dylib_dir/$basename"
        copied=1
      fi
    done < <(
      find_macho_files "$APP_BUNDLE" \
        | while IFS= read -r binary; do
          homebrew_dependencies_for "$binary"
        done \
        | /usr/bin/sort -u
    )
  done

  find_macho_files "$APP_BUNDLE" | while IFS= read -r binary; do
    while IFS= read -r dep; do
      local basename
      basename="$(/usr/bin/basename "$dep")"
      /usr/bin/install_name_tool \
        -change "$dep" "@executable_path/../Frameworks/Homebrew/$basename" \
        "$binary"
    done < <(homebrew_dependencies_for "$binary")
  done

  find_macho_files "$dylib_dir" | while IFS= read -r dylib; do
    /usr/bin/install_name_tool \
      -id "@executable_path/../Frameworks/Homebrew/$(/usr/bin/basename "$dylib")" \
      "$dylib" || true
  done
}

verify_no_homebrew_references() {
  local remaining_refs="$DIST_DIR/homebrew-dylib-references.txt"
  /bin/mkdir -p "$DIST_DIR"

  find_macho_files "$APP_BUNDLE" \
    | while IFS= read -r binary; do
      homebrew_dependencies_for "$binary"
    done \
    | /usr/bin/sort -u > "$remaining_refs"

  if [[ -s "$remaining_refs" ]]; then
    /bin/cat "$remaining_refs" >&2
    fail "App bundle still contains /opt/homebrew dylib references."
  fi
}

sign_app_bundle() {
  local entitlements_path="$1"

  [[ -d "$APP_BUNDLE" ]] || fail "App bundle not found at $APP_BUNDLE."

  if [[ -d "$APP_BUNDLE/Contents/Frameworks" ]]; then
    while IFS= read -r path; do
      if /usr/bin/file "$path" | /usr/bin/grep -q "Mach-O"; then
        sign_path "$path"
      fi
    done < <(/usr/bin/find "$APP_BUNDLE/Contents/Frameworks" -type f)

    while IFS= read -r path; do
      sign_path "$path"
    done < <(/usr/bin/find "$APP_BUNDLE/Contents/Frameworks" -type d -name "*.framework" -prune)
  fi

  /usr/bin/codesign \
    --force \
    --sign "$SIGN_IDENTITY" \
    --options runtime \
    --timestamp \
    --entitlements "$entitlements_path" \
    "$APP_BUNDLE"
}

verify_app_bundle() {
  /usr/bin/codesign --verify --deep --strict --verbose=4 "$APP_BUNDLE"
  local entitlements_out="$DIST_DIR/$APP_NAME.entitlements.actual.plist"
  /usr/bin/codesign -d --entitlements :- "$APP_BUNDLE" > "$entitlements_out"
  /usr/bin/plutil -lint "$entitlements_out" >/dev/null
  /usr/sbin/spctl -a -vv --type exec "$APP_BUNDLE" || true
}

build_app_bundle() {
  flutter build macos --release --config-only "$@"

  /usr/bin/xcodebuild \
    -resolvePackageDependencies \
    -workspace "$ROOT_DIR/macos/Runner.xcworkspace" \
    -scheme Runner \
    -derivedDataPath "$ROOT_DIR/build/macos"

  /usr/bin/xcodebuild \
    -workspace "$ROOT_DIR/macos/Runner.xcworkspace" \
    -scheme Runner \
    -configuration Release \
    -derivedDataPath "$ROOT_DIR/build/macos" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY= \
    build
}

notarize_file() {
  local path="$1"

  if [[ "$SKIP_NOTARIZATION" == "1" ]]; then
    echo "Skipping notarization for local testing: $path"
    return
  fi

  /usr/bin/xcrun notarytool submit "$path" --keychain-profile "$NOTARY_PROFILE" --wait
}

notarize_and_staple_app() {
  local zip_path="$DIST_DIR/$APP_NAME.app.zip"
  /bin/rm -f "$zip_path"
  /usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$zip_path"
  notarize_file "$zip_path"

  if [[ "$SKIP_NOTARIZATION" != "1" ]]; then
    /usr/bin/xcrun stapler staple "$APP_BUNDLE"
    /usr/bin/xcrun stapler validate "$APP_BUNDLE"
    verify_app_bundle
  fi
}

create_signed_dmg() {
  local staging_dir
  staging_dir="$(/usr/bin/mktemp -d "/private/tmp/mixroom-dmg.XXXXXX")"

  /bin/rm -f "$DMG_PATH"
  /bin/mkdir -p "$DIST_DIR"
  /bin/cp -R "$APP_BUNDLE" "$staging_dir/$APP_NAME.app"
  /bin/ln -s /Applications "$staging_dir/Applications"

  /usr/bin/hdiutil create \
    -volname "$DMG_VOLUME_NAME" \
    -srcfolder "$staging_dir" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

  /usr/bin/codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
  /usr/bin/codesign --verify --verbose=4 "$DMG_PATH"

  /usr/bin/hdiutil attach -nobrowse -readonly "$DMG_PATH" >/dev/null
  local mounted_app="/Volumes/$DMG_VOLUME_NAME/$APP_NAME.app"
  /usr/bin/codesign --verify --deep --strict --verbose=4 "$mounted_app"
  /usr/bin/hdiutil detach "/Volumes/$DMG_VOLUME_NAME" >/dev/null
}

notarize_and_staple_dmg() {
  notarize_file "$DMG_PATH"

  if [[ "$SKIP_NOTARIZATION" != "1" ]]; then
    /usr/bin/xcrun stapler staple "$DMG_PATH"
    /usr/bin/xcrun stapler validate "$DMG_PATH"
    /usr/sbin/spctl -a -vv --type open --context context:primary-signature "$DMG_PATH"
  fi
}

main() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
  fi

  require_tools
  prepare_identity

  cd "$ROOT_DIR"
  if [[ "$SKIP_BUILD" == "1" ]]; then
    [[ -d "$APP_BUNDLE" ]] || fail "MACOS_SKIP_BUILD=1 was set, but app bundle does not exist at $APP_BUNDLE."
  else
    build_app_bundle "$@"
  fi

  local entitlements_path
  entitlements_path="$(expanded_entitlements_path)"

  embed_homebrew_dylibs
  verify_no_homebrew_references
  sign_app_bundle "$entitlements_path"
  verify_app_bundle
  notarize_and_staple_app
  create_signed_dmg
  notarize_and_staple_dmg

  echo "Created distributable DMG: $DMG_PATH"
}

main "$@"
