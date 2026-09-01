#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Mixroom"
APP_BUNDLE="$ROOT_DIR/build/macos/Build/Products/Release/$APP_NAME.app"
DIST_DIR="$ROOT_DIR/build/distribution"
DMG_BACKGROUND_SRC="$ROOT_DIR/assets/macos/installer-background.svg"
ENTITLEMENTS_SRC="$ROOT_DIR/macos/Runner/Release.entitlements"
HOMEBREW_BUNDLER="$ROOT_DIR/tool/bundle_macos_homebrew_dylibs.sh"
GENERATED_ENTITLEMENTS="$ROOT_DIR/build/macos/Build/Intermediates.noindex/Runner.build/Release/Runner.build/$APP_NAME.app.xcent"
TEAM_ID="${MACOS_TEAM_ID:-X8Y4B4222A}"
BUNDLE_ID="${MACOS_BUNDLE_ID:-com.mixroom.mixroomapp}"
SIGN_IDENTITY="${MACOS_CODESIGN_IDENTITY:-}"
NOTARY_PROFILE="${MACOS_NOTARY_KEYCHAIN_PROFILE:-}"
DMG_PATH="${MACOS_DMG_PATH:-$DIST_DIR/$APP_NAME-macOS.dmg}"
UPDATE_ZIP_PATH="${MACOS_UPDATE_ZIP_PATH:-$DIST_DIR/$APP_NAME-macOS.zip}"
DMG_VOLUME_NAME="${MACOS_DMG_VOLUME_NAME:-$APP_NAME Installer}"
SKIP_NOTARIZATION="${MACOS_SKIP_NOTARIZATION:-0}"
SKIP_BUILD="${MACOS_SKIP_BUILD:-0}"
RELEASE_ARCH="${MACOS_RELEASE_ARCH:-arm64}"

usage() {
  cat >&2 <<EOF
usage: $0 [flutter build macos args...]

Required for distributable builds:
  MACOS_CODESIGN_IDENTITY          Developer ID Application identity name.
                                  If omitted, the first installed Developer ID Application identity is used.
                                  Set to "-" with MACOS_SKIP_NOTARIZATION=1 for an ad-hoc signed test build.
  MACOS_NOTARY_KEYCHAIN_PROFILE    notarytool keychain profile name.
                                  Required unless MACOS_SKIP_NOTARIZATION=1.

Optional:
  MACOS_TEAM_ID                    Apple Developer Team ID. Defaults to X8Y4B4222A.
  MACOS_DMG_PATH                   Output DMG path. Defaults to build/distribution/Mixroom-macOS.dmg.
  MACOS_UPDATE_ZIP_PATH            Sparkle update archive. Defaults to build/distribution/Mixroom-macOS.zip.
  MACOS_DMG_VOLUME_NAME            Mounted DMG volume name. Defaults to "Mixroom Installer".
  MACOS_SKIP_NOTARIZATION=1        Build a signed-but-not-notarized DMG for local testing only.
  MACOS_SKIP_BUILD=1               Re-sign/package the existing Release app without rebuilding it.
  MACOS_RELEASE_ARCH               Architecture shipped in the DMG. Defaults to arm64.
                                  Use x86_64 only with matching Intel Homebrew dependencies.
  MACOS_KEEP_RESTRICTED_ENTITLEMENTS=1
                                  Keep profile-gated entitlements for diagnostic builds.
  MACOS_STRIP_KEYCHAIN_ACCESS_GROUPS=1
                                  Force-strip keychain access groups, including diagnostic builds.
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
  if [[ "$SKIP_NOTARIZATION" == "1" ]]; then
    if [[ "$DMG_PATH" == "$DIST_DIR/$APP_NAME-macOS.dmg" ]]; then
      DMG_PATH="$DIST_DIR/$APP_NAME-macOS-UNSIGNED-TEST-ONLY.dmg"
    fi
    if [[ "$UPDATE_ZIP_PATH" == "$DIST_DIR/$APP_NAME-macOS.zip" ]]; then
      UPDATE_ZIP_PATH="$DIST_DIR/$APP_NAME-macOS-UNSIGNED-TEST-ONLY.zip"
    fi
  fi

  if [[ -z "$SIGN_IDENTITY" ]]; then
    SIGN_IDENTITY="$(find_developer_id_identity)"
  fi

  [[ -n "$SIGN_IDENTITY" ]] || fail "No Developer ID Application signing identity found. Install the certificate or set MACOS_CODESIGN_IDENTITY."

  if [[ "$SKIP_NOTARIZATION" != "1" && -z "$NOTARY_PROFILE" ]]; then
    fail "MACOS_NOTARY_KEYCHAIN_PROFILE is required for employee/customer DMG distribution."
  fi
}

validate_release_arch() {
  case "$RELEASE_ARCH" in
    arm64|x86_64) ;;
    *) fail "MACOS_RELEASE_ARCH must be arm64 or x86_64." ;;
  esac
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
    /usr/libexec/PlistBuddy -c "Delete :keychain-access-groups" "$entitlements_path" >/dev/null 2>&1 || true
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

  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    /usr/bin/codesign --force --sign "$SIGN_IDENTITY" --options runtime "$path"
  else
    /usr/bin/codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$path"
  fi
}

find_macho_files() {
  local root="$1"

  /usr/bin/find "$root" -type f -print0 | while IFS= read -r -d '' path; do
    if /usr/bin/file "$path" | /usr/bin/grep -q "Mach-O"; then
      /bin/echo "$path"
    fi
  done
}

resolve_homebrew_dependency() {
  local dep="$1"

  if [[ -f "$dep" ]]; then
    echo "$dep"
    return
  fi

  if [[ "$dep" == *"*"* ]]; then
    local basename
    basename="$(/usr/bin/basename "$dep")"

    local candidate
    for candidate in \
      "/opt/homebrew/lib/$basename" \
      "/opt/homebrew/opt/"*/"lib/$basename" \
      "/opt/homebrew/Cellar/"*/*/"lib/$basename"; do
      if [[ -f "$candidate" ]]; then
        echo "$candidate"
        return
      fi
    done
  fi

  return 1
}

homebrew_dependencies_for() {
  local binary="$1"
  /usr/bin/otool -L "$binary" \
    | /usr/bin/awk '/\/(opt\/homebrew|usr\/local)\// { print $1 }'
}

embed_homebrew_dylibs() {
  [[ -x "$HOMEBREW_BUNDLER" ]] || fail "Homebrew dependency bundler is missing or not executable: $HOMEBREW_BUNDLER"
  "$HOMEBREW_BUNDLER" "$APP_BUNDLE"
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
    fail "App bundle still contains Homebrew dylib references."
  fi
}

normalize_embedded_framework_ids() {
  local frameworks_dir="$APP_BUNDLE/Contents/Frameworks"
  [[ -d "$frameworks_dir" ]] || return

  local framework executable binary version install_name
  for framework in "$frameworks_dir"/*.framework; do
    [[ -d "$framework" ]] || continue

    executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' \
      "$framework/Resources/Info.plist" 2>/dev/null || true)"
    [[ -n "$executable" ]] || continue

    version=""
    if [[ -L "$framework/Versions/Current" ]]; then
      version="$(/usr/bin/readlink "$framework/Versions/Current")"
      binary="$framework/Versions/$version/$executable"
      install_name="@rpath/$(/usr/bin/basename "$framework")/Versions/$version/$executable"
    else
      binary="$framework/$executable"
      install_name="@rpath/$(/usr/bin/basename "$framework")/$executable"
    fi

    [[ -f "$binary" ]] || continue
    if /usr/bin/otool -D "$binary" 2>/dev/null | /usr/bin/grep -q '/private/var/'; then
      /usr/bin/install_name_tool -id "$install_name" "$binary"
    fi
  done
}

thin_macho_files_to_release_arch() {
  local thin_path="$DIST_DIR/.thin-macho"
  /bin/mkdir -p "$DIST_DIR"

  find_macho_files "$APP_BUNDLE" \
    | while IFS= read -r binary; do
      /usr/bin/lipo "$binary" -verify_arch "$RELEASE_ARCH" >/dev/null 2>&1 \
        || fail "Required $RELEASE_ARCH slice is missing: $binary"

      local architectures
      architectures="$(/usr/bin/lipo -archs "$binary")"
      if [[ "$architectures" == *" "* ]]; then
        local file_mode
        file_mode="$(/usr/bin/stat -f '%Lp' "$binary")"
        /usr/bin/lipo "$binary" -thin "$RELEASE_ARCH" -output "$thin_path"
        /bin/chmod "$file_mode" "$thin_path"
        /bin/mv -f "$thin_path" "$binary"
      fi
    done
}

verify_macho_dependencies() {
  local missing_refs="$DIST_DIR/missing-dylib-references.txt"
  /bin/mkdir -p "$DIST_DIR"
  : > "$missing_refs"

  find_macho_files "$APP_BUNDLE" \
    | while IFS= read -r binary; do
      /usr/bin/otool -L "$binary" \
        | /usr/bin/awk 'NR > 1 { print $1 }' \
        | while IFS= read -r dependency; do
          case "$dependency" in
            /System/*|/usr/lib/*|@rpath/*|@loader_path/*|@executable_path/*)
              ;;
            /*)
              if [[ ! -e "$dependency" ]]; then
                /bin/echo "$binary -> $dependency" >> "$missing_refs"
              fi
              ;;
          esac
        done
    done

  if [[ -s "$missing_refs" ]]; then
    /bin/cat "$missing_refs" >&2
    fail "App bundle contains unresolved absolute dynamic-library references."
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

  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    /usr/bin/codesign \
      --force \
      --sign "$SIGN_IDENTITY" \
      --options runtime \
      --entitlements "$entitlements_path" \
      "$APP_BUNDLE"
  else
    /usr/bin/codesign \
      --force \
      --sign "$SIGN_IDENTITY" \
      --options runtime \
      --timestamp \
      --entitlements "$entitlements_path" \
      "$APP_BUNDLE"
  fi
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
    -workspace "$ROOT_DIR/macos/Runner.xcworkspace" \
    -scheme Runner \
    -configuration Release \
    -derivedDataPath "$ROOT_DIR/build/macos" \
    clean

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

create_update_zip() {
  /bin/rm -f "$UPDATE_ZIP_PATH"
  /bin/mkdir -p "$(/usr/bin/dirname "$UPDATE_ZIP_PATH")"
  /usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$UPDATE_ZIP_PATH"
}

create_signed_dmg() {
  local staging_dir writable_dmg mount_dir mounted=0 background_dir background_png background_thumbnail_dir=""
  staging_dir="$(/usr/bin/mktemp -d "/private/tmp/mixroom-dmg.XXXXXX")"
  mount_dir="/Volumes/$DMG_VOLUME_NAME"
  writable_dmg="$DIST_DIR/.${APP_NAME}-macOS-layout.dmg"
  background_dir="$staging_dir/.background"
  background_png="$background_dir/installer-background-v57.png"

  cleanup_dmg_layout() {
    if [[ "$mounted" == "1" ]]; then
      /usr/bin/hdiutil detach "$mount_dir" >/dev/null 2>&1 || true
    fi
    /bin/rm -rf "$staging_dir"
    if [[ -n "$background_thumbnail_dir" ]]; then
      /bin/rm -rf "$background_thumbnail_dir"
    fi
  }
  trap cleanup_dmg_layout EXIT

  /bin/rm -f "$DMG_PATH"
  /bin/rm -f "$writable_dmg"
  /bin/mkdir -p "$DIST_DIR"
  /bin/cp -R "$APP_BUNDLE" "$staging_dir/$APP_NAME.app"
  /bin/ln -s /Applications "$staging_dir/Applications"
  [[ -f "$DMG_BACKGROUND_SRC" ]] || fail "DMG background source is missing: $DMG_BACKGROUND_SRC"
  /bin/mkdir -p "$background_dir"
  background_thumbnail_dir="$(/usr/bin/mktemp -d "/private/tmp/mixroom-dmg-background.XXXXXX")"
  /bin/cp "$DMG_BACKGROUND_SRC" "$background_thumbnail_dir/installer-background-v57.svg"
  /usr/bin/qlmanage -t -s 1200 -o "$background_thumbnail_dir" \
    "$background_thumbnail_dir/installer-background-v57.svg" >/dev/null
  /usr/bin/sips -z 340 600 "$background_thumbnail_dir/installer-background-v57.svg.png" \
    --out "$background_png" >/dev/null
  /bin/rm -rf "$background_thumbnail_dir"
  background_thumbnail_dir=""

  /usr/bin/hdiutil create \
    -volname "$DMG_VOLUME_NAME" \
    -srcfolder "$staging_dir" \
    -ov \
    -format UDRW \
    "$writable_dmg"

  [[ ! -e "$mount_dir" ]] \
    || fail "Close and eject the existing '$DMG_VOLUME_NAME' volume before packaging."
  /usr/bin/hdiutil attach \
    -readwrite \
    -noverify \
    -noautoopen \
    "$writable_dmg" >/dev/null
  [[ -d "$mount_dir" ]] || fail "DMG mounted somewhere other than the canonical path: $mount_dir"
  mounted=1
  /bin/sleep 2

  /usr/bin/osascript <<EOF
tell application "Finder"
  tell disk "$DMG_VOLUME_NAME"
    open
    set dmgWindow to container window
    set current view of dmgWindow to icon view
    set toolbar visible of dmgWindow to false
    set statusbar visible of dmgWindow to false
    set the bounds of dmgWindow to {100, 100, 700, 460}
    set layoutOptions to icon view options of dmgWindow
    set arrangement of layoutOptions to not arranged
    set icon size of layoutOptions to 112
    set text size of layoutOptions to 14
    set background picture of layoutOptions to file ".background:installer-background-v57.png"
    set position of item "$APP_NAME.app" of dmgWindow to {150, 166}
    set position of item "Applications" of dmgWindow to {450, 166}
    close dmgWindow
    open
    update without registering applications
    delay 3
  end tell
end tell
EOF

  /bin/sync
  [[ -f "$mount_dir/.DS_Store" ]] || fail "Finder did not persist the installer layout to .DS_Store."
  /usr/bin/hdiutil detach "$mount_dir" >/dev/null
  mounted=0
  /usr/bin/hdiutil convert \
    "$writable_dmg" \
    -ov \
    -format UDZO \
    -o "$DMG_PATH" >/dev/null
  /bin/rm -f "$writable_dmg"
  cleanup_dmg_layout
  trap - EXIT

  if [[ "$SIGN_IDENTITY" != "-" ]]; then
    /usr/bin/codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
    /usr/bin/codesign --verify --verbose=4 "$DMG_PATH"
  fi

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
  validate_release_arch
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
  normalize_embedded_framework_ids
  thin_macho_files_to_release_arch
  verify_no_homebrew_references
  verify_macho_dependencies
  sign_app_bundle "$entitlements_path"
  verify_app_bundle
  notarize_and_staple_app
  create_update_zip
  create_signed_dmg
  notarize_and_staple_dmg

  echo "Created distributable DMG: $DMG_PATH"
  echo "Created Sparkle update archive: $UPDATE_ZIP_PATH"
}

main "$@"
