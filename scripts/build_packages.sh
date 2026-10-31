#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT_DIR/ChargeGuard.xcodeproj"
OUT_DIR="$ROOT_DIR/out"
PKG_ROOTFUL_DIR="$ROOT_DIR/ChargeLimiter/Package"
PKG_ROOTLESS_DIR="$ROOT_DIR/ChargeLimiter/Package_rootless"
PKG_ROOTHIDE_DIR="$ROOT_DIR/ChargeLimiter/Package_roothide"
TWEAK_SRC_DIR="$ROOT_DIR/ChargeLimiter/Tweak"
TWEAK_NAME="CLThermalSim"
BUILD_ROOTFUL="$ROOT_DIR/build_rootful"
BUILD_ROOTLESS="$ROOT_DIR/build_rootless"
BUILD_ROOTHIDE="$ROOT_DIR/build_roothide"
PAYLOAD_DIR="$ROOT_DIR/Payload"
ROOTHIDE_MERGE_ENT="$ROOT_DIR/scripts/roothide.entitlements"
STAGE_DIR=""
BUILD_LOG_ROOT=""
# Default: native roothide scheme + Package_roothide.
BUILD_NATIVE_ROOTHIDE="${CHARGELIMITER_BUILD_NATIVE_ROOTHIDE:-1}"
DPKG_DEB_SUPPORTS_ROOT_OWNER_GROUP=0

# CHARGELIMITER_BUILD_ROOTHIDE=0 disables all roothide packaging paths.
case "${CHARGELIMITER_BUILD_ROOTHIDE:-1}" in
  0)
    BUILD_NATIVE_ROOTHIDE=0
    ;;
  1)
    ;;
  *)
    echo "[ERR] CHARGELIMITER_BUILD_ROOTHIDE must be 0 or 1." >&2
    exit 1
    ;;
esac

usage() {
  cat >&2 <<EOF
Usage: $0 [VERSION] [--skip-roothide]

Build TrollStore, rootful, rootless, and roothide packages into out/.

By default the roothide package is built natively via the "ChargeGuard roothide"
scheme and Package_roothide template (THEOS_PACKAGE_SCHEME=roothide).

Options:
  --skip-roothide            Do not build the roothide package.
EOF
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "[ERR] Missing command: $1" >&2
        exit 1
    }
}

require_cmd xcodebuild
require_cmd dpkg-deb
require_cmd zip
require_cmd ldid
require_cmd plutil
require_cmd xcrun
require_cmd rg

if dpkg-deb --help 2>&1 | grep -q -- '--root-owner-group'; then
  DPKG_DEB_SUPPORTS_ROOT_OWNER_GROUP=1
fi

run_logged_command() {
  log_name="$1"
  shift

  if [ -z "$BUILD_LOG_ROOT" ]; then
    BUILD_LOG_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/chargelimiter-build-logs.XXXXXX")"
  fi

  log_path="$BUILD_LOG_ROOT/${log_name}.log"
  if "$@" >"$log_path" 2>&1; then
    return 0
  fi

  status=$?
  echo "[ERR] Command failed: $*" >&2
  echo "[ERR] Build log: $log_path" >&2
  echo "[ERR] Last 200 log lines:" >&2
  tail -n 200 "$log_path" >&2 || true
  exit "$status"
}

dpkg_build_package() {
  stage_path="$1"
  out_path="$2"

  if [ "$DPKG_DEB_SUPPORTS_ROOT_OWNER_GROUP" = "1" ]; then
    dpkg-deb --root-owner-group -Zxz -b "$stage_path" "$out_path" >/dev/null
  else
    dpkg-deb -Zxz -b "$stage_path" "$out_path" >/dev/null
  fi
}

force_clean_dir() {
  dir="$1"
  [ -e "$dir" ] || return 0

  attempts=0
  while [ "$attempts" -lt 5 ] && [ -e "$dir" ]; do
    rm -rf "$dir" 2>/dev/null || true
    if [ -e "$dir" ]; then
      # Handle transient ENOTEMPTY / permission edge cases on macOS.
      chmod -R u+w "$dir" 2>/dev/null || true
      find "$dir" -mindepth 1 -exec rm -rf {} + 2>/dev/null || true
      rm -rf "$dir" 2>/dev/null || true
    fi
    attempts=$((attempts + 1))
    [ -e "$dir" ] && sleep 1 || true
  done

  if [ -e "$dir" ]; then
    echo "[ERR] Failed to clean directory: $dir" >&2
    exit 1
  fi
}

clean_host_metadata() {
  dir="$1"
  [ -d "$dir" ] || return 0
  find "$dir" \( -name .DS_Store -o -name __MACOSX -o -name '._*' \) -exec rm -rf {} + 2>/dev/null || true
}

clean_known_outputs() {
  [ -d "$OUT_DIR" ] || return 0
  find "$OUT_DIR" -maxdepth 1 -type f -name 'ChargeGuard_*' -delete
}

# Ensure local link stubs under ChargeLimiter/ for Xcode LIBRARY_SEARCH_PATHS
# ($(PROJECT_DIR)/ChargeLimiter). Prefer Theos vendor paths; never commit these.
ensure_local_libroot_stubs() {
  dest_a="$ROOT_DIR/ChargeLimiter/libroot.a"
  dest_tbd="$ROOT_DIR/ChargeLimiter/libroothide.tbd"

  if [ ! -f "$dest_a" ]; then
    for candidate in \
      /opt/theos/vendor/lib/iphone/roothide/libroot.a \
      /opt/theos/vendor/lib/libroot.a \
      /opt/theos/vendor/lib/iphone/rootless/libroot.a \
      /opt/theos_roothide/vendor/lib/iphone/roothide/libroot.a \
      /opt/theos_roothide/vendor/lib/libroot.a
    do
      if [ -f "$candidate" ]; then
        cp -a "$candidate" "$dest_a"
        echo "[INFO] Placed local libroot.a from $candidate"
        break
      fi
    done
  fi

  if [ ! -f "$dest_tbd" ]; then
    for candidate in \
      /opt/theos/vendor/lib/iphone/roothide/libroothide.tbd \
      /opt/theos/vendor/lib/libroothide.tbd \
      /opt/theos_roothide/vendor/lib/iphone/roothide/libroothide.tbd \
      /opt/theos_roothide/vendor/lib/libroothide.tbd
    do
      if [ -f "$candidate" ]; then
        cp -a "$candidate" "$dest_tbd"
        echo "[INFO] Placed local libroothide.tbd from $candidate"
        break
      fi
    done
  fi
}

require_project_build_environment() {
  missing=0
  for header in \
    IOKit/hid/IOHIDService.h \
    MobileCoreServices/LSApplicationProxy.h
  do
    found=0
    for include_root in /opt/theos/vendor/include /opt/include; do
      if [ -f "$include_root/$header" ]; then
        found=1
        break
      fi
    done

    if [ "$found" -ne 1 ]; then
      echo "[ERR] Missing build dependency header: $header" >&2
      missing=1
    fi
  done

  if [ "$missing" -ne 0 ]; then
    echo "[ERR] Prepare Theos headers before building. This project searches /opt/theos/vendor/include and /opt/include." >&2
    echo "[ERR] Example: clone Theos to /opt/theos; /opt/include may also point to /opt/theos/vendor/include." >&2
    exit 1
  fi

  ensure_local_libroot_stubs

  # rootless + native roothide both link -lroot
  if [ ! -f "$ROOT_DIR/ChargeLimiter/libroot.a" ] \
    && [ ! -f /opt/theos/vendor/lib/iphone/rootless/libroot.a ] \
    && [ ! -f /opt/theos/vendor/lib/libroot.a ] \
    && [ ! -f /opt/theos/vendor/lib/iphone/roothide/libroot.a ]
  then
    echo "[ERR] Missing libroot.a for -lroot (rootless/roothide)." >&2
    echo "[ERR] Place it under /opt/theos/vendor/lib/iphone/roothide/ or /opt/theos/vendor/lib/," >&2
    echo "[ERR] or let ensure_local_libroot_stubs copy it into ChargeLimiter/libroot.a." >&2
    exit 1
  fi

  if [ "$BUILD_NATIVE_ROOTHIDE" = "1" ]; then
    if [ ! -d /opt/theos/vendor/include/roothide ] && [ ! -f /opt/theos/vendor/include/roothide.h ]; then
      echo "[WARN] roothide headers not found under /opt/theos/vendor/include/roothide; native build may still link via libroot only." >&2
    fi
  fi
}

copy_tree_contents() {
  src_dir="$1"
  dst_dir="$2"
  [ -d "$src_dir" ] || return 0
  mkdir -p "$dst_dir"
  cp -a "$src_dir"/. "$dst_dir"/
}

set_control_version() {
  control_file="$1"
  tmp_file="${control_file}.tmp.$$"
  awk -v ver="$VERSION" '
    BEGIN { done = 0 }
    /^Version:[[:space:]]*/ { print "Version: " ver; done = 1; next }
    { print }
    END { if (!done) print "Version: " ver }
  ' "$control_file" > "$tmp_file"
  mv "$tmp_file" "$control_file"
}

set_roothide_control_arch() {
  control_file="$1"
  tmp_file="${control_file}.tmp.$$"
  awk '
    BEGIN { done = 0 }
    /^Architecture:[[:space:]]*/ { print "Architecture: iphoneos-arm64e"; done = 1; next }
    NF { print }
    END { if (!done) print "Architecture: iphoneos-arm64e" }
  ' "$control_file" > "$tmp_file"
  mv "$tmp_file" "$control_file"
}

sign_app() {
  APP_PATH="$1"
  APP_ENT="$2"
  [ -f "$APP_PATH/ChargeGuard" ] || { echo "[ERR] Missing binary: $APP_PATH/ChargeGuard" >&2; exit 1; }
  [ -f "$APP_PATH/ChargeGuardDaemon" ] || { echo "[ERR] Missing binary: $APP_PATH/ChargeGuardDaemon" >&2; exit 1; }
  # Align with common TrollStore packaging flow: sign app bundle entry.
  ldid -S"$APP_ENT" "$APP_PATH"
  # Keep dedicated entitlements for each executable.
  ldid -S"$APP_ENT" "$APP_PATH/ChargeGuard"
  ldid -S"$DAEMON_ENT" "$APP_PATH/ChargeGuardDaemon"
  rm -rf "$APP_PATH/_CodeSignature"
}

# Native roothide: base jb entitlements, then merge scripts/roothide.entitlements.
sign_roothide_app() {
  APP_PATH="$1"
  sign_app "$APP_PATH" "$APP_ENT_JB"
  ldid -M "-S$ROOTHIDE_MERGE_ENT" "$APP_PATH/ChargeGuard"
  ldid -M "-S$ROOTHIDE_MERGE_ENT" "$APP_PATH/ChargeGuardDaemon"
  rm -rf "$APP_PATH/_CodeSignature"
}

# Companion tweak dylib for thermalmonitord injection (design D6):
# compiled directly with clang per package arch, fake-signed with ldid; no Theos/Logos.
build_tweak_dylib() {
  TWEAK_ARCH="$1"
  TWEAK_OUT="$2"
  plutil -lint "$TWEAK_SRC_DIR/$TWEAK_NAME.plist" >/dev/null
  xcrun -sdk iphoneos clang -dynamiclib \
    -arch "$TWEAK_ARCH" \
    -fobjc-arc \
    -miphoneos-version-min=11.0 \
    -framework Foundation \
    "$ROOT_DIR/ChargeLimiter/IOKit.tbd" \
    "$TWEAK_SRC_DIR/CLThermalSimTweak.m" \
    -o "$TWEAK_OUT"
  ldid -S "$TWEAK_OUT"
}

stage_tweak_files() {
  STAGE_TREE="$1"
  TWEAK_DYLIB="$2"
  mkdir -p "$STAGE_TREE/Library/MobileSubstrate/DynamicLibraries"
  cp -p "$TWEAK_DYLIB" "$STAGE_TREE/Library/MobileSubstrate/DynamicLibraries/$TWEAK_NAME.dylib"
  cp -p "$TWEAK_SRC_DIR/$TWEAK_NAME.plist" "$STAGE_TREE/Library/MobileSubstrate/DynamicLibraries/$TWEAK_NAME.plist"
  chmod 755 "$STAGE_TREE/Library/MobileSubstrate/DynamicLibraries/$TWEAK_NAME.dylib"
  chmod 644 "$STAGE_TREE/Library/MobileSubstrate/DynamicLibraries/$TWEAK_NAME.plist"
}

strip_app() {
  APP_PATH="$1"
  xcrun strip -S -x "$APP_PATH/ChargeGuard"
  xcrun strip -S -x "$APP_PATH/ChargeGuardDaemon"
}

list_rpaths() {
  xcrun otool -l "$1" |
  awk '
    /^[^ ]/ { in_rpath = 0 }
    $1 == "cmd" && $2 == "LC_RPATH" { in_rpath = 1; next }
    in_rpath && $1 == "path" { print $2; in_rpath = 0 }
  '
}

cleanup() {
  status=$?

  if [ -n "$STAGE_DIR" ]; then
    rm -rf "$STAGE_DIR"
  fi

  if [ -d "$PAYLOAD_DIR" ]; then
    rm -rf "$PAYLOAD_DIR"
  fi

  if [ -n "$BUILD_LOG_ROOT" ] && [ -d "$BUILD_LOG_ROOT" ]; then
    rm -rf "$BUILD_LOG_ROOT"
  fi

  return "$status"
}

trap cleanup EXIT INT TERM

VERSION=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --skip-roothide)
      BUILD_NATIVE_ROOTHIDE=0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "[ERR] Unknown option: $1" >&2
      usage
      exit 1
      ;;
    *)
      if [ -n "$VERSION" ]; then
        echo "[ERR] Version was provided more than once." >&2
        usage
        exit 1
      fi
      VERSION="$1"
      ;;
  esac
  shift
done

case "$BUILD_NATIVE_ROOTHIDE" in
  0|1)
    ;;
  *)
    echo "[ERR] CHARGELIMITER_BUILD_NATIVE_ROOTHIDE must be 0 or 1." >&2
    exit 1
    ;;
esac

BUILD_ANY_ROOTHIDE=0
if [ "$BUILD_NATIVE_ROOTHIDE" = "1" ]; then
  BUILD_ANY_ROOTHIDE=1
fi

if [ "$BUILD_ANY_ROOTHIDE" = "1" ]; then
  [ -f "$ROOTHIDE_MERGE_ENT" ] || {
    echo "[ERR] Missing roothide compatibility entitlements: $ROOTHIDE_MERGE_ENT" >&2
    exit 1
  }
fi

if [ -z "$VERSION" ]; then
    VERSION="$(awk -F' = ' '/MARKETING_VERSION =/{gsub(/;/, "", $2); print $2; exit}' "$ROOT_DIR/ChargeGuard.xcodeproj/project.pbxproj")"
fi

if [ -z "$VERSION" ]; then
    echo "[ERR] Unable to resolve version." >&2
    exit 1
fi

ROOTFUL_APP="$BUILD_ROOTFUL/Build/Products/Release-iphoneos/ChargeGuard.app"
ROOTLESS_APP="$BUILD_ROOTLESS/Build/Products/Release-iphoneos/ChargeGuard.app"
ROOTHIDE_APP="$BUILD_ROOTHIDE/Build/Products/Release-iphoneos/ChargeGuard.app"
APP_ENT_TS="$ROOT_DIR/ChargeLimiter/ChargeLimiter.app.entitlements"
APP_ENT_JB="$ROOT_DIR/ChargeLimiter/ChargeLimiter.app.jb.entitlements"
DAEMON_ENT="$ROOT_DIR/ChargeLimiter/ChargeLimiter.entitlements"

TIPA_OUT="$OUT_DIR/ChargeGuard_${VERSION}_TrollStore.tipa"
ROOTFUL_DEB_OUT="$OUT_DIR/ChargeGuard_${VERSION}_rootful_arm.deb"
ROOTLESS_DEB_OUT="$OUT_DIR/ChargeGuard_${VERSION}_rootless_arm64.deb"
ROOTHIDE_DEB_OUT="$OUT_DIR/ChargeGuard_${VERSION}_roothide_arm64e.deb"
TROLLSTORE_BANNED_ENTITLEMENTS_REGEX="com\\.apple\\.private\\.cs\\.debugger|dynamic-codesigning|com\\.apple\\.private\\.skip-library-validation"

force_clean_dir "$BUILD_ROOTFUL"
force_clean_dir "$BUILD_ROOTLESS"
force_clean_dir "$BUILD_ROOTHIDE"
force_clean_dir "$PAYLOAD_DIR"
require_project_build_environment
mkdir -p "$OUT_DIR" "$PAYLOAD_DIR"
clean_known_outputs
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/chargelimiter-pack.XXXXXX")"
STAGE_ROOTFUL_DIR="$STAGE_DIR/rootful"
STAGE_ROOTLESS_DIR="$STAGE_DIR/rootless"
STAGE_ROOTHIDE_DIR="$STAGE_DIR/roothide"

echo "[1/10] Build rootful app (arm64)..."
run_logged_command build-rootful xcodebuild \
  -project "$PROJECT" \
  -scheme "ChargeGuard" \
  -destination "generic/platform=iOS" \
  -configuration Release \
  -derivedDataPath "$BUILD_ROOTFUL" \
  CODE_SIGNING_ALLOWED=NO \
  THEOS_PACKAGE_SCHEME= \
  THEOS_PACKAGE_INSTALL_PREFIX= \
  ARCHS=arm64 \
  MonkeyDevInstallOnAnyBuild=NO \
  MonkeyDevBuildPackageOnAnyBuild=NO

echo "[2/10] Build rootless app (arm64)..."
run_logged_command build-rootless xcodebuild \
  -project "$PROJECT" \
  -scheme "ChargeGuard rootless" \
  -destination "generic/platform=iOS" \
  -configuration Release \
  -derivedDataPath "$BUILD_ROOTLESS" \
  CODE_SIGNING_ALLOWED=NO \
  THEOS_PACKAGE_SCHEME=rootless \
  THEOS_PACKAGE_INSTALL_PREFIX=/var/jb \
  ARCHS=arm64 \
  MonkeyDevInstallOnAnyBuild=NO \
  MonkeyDevBuildPackageOnAnyBuild=NO

if [ "$BUILD_NATIVE_ROOTHIDE" = "1" ]; then
  echo "[3/10] Build roothide app (native scheme)..."
  run_logged_command build-roothide xcodebuild \
    -project "$PROJECT" \
    -scheme "ChargeGuard roothide" \
    -destination "generic/platform=iOS" \
    -configuration Release \
    -derivedDataPath "$BUILD_ROOTHIDE" \
    CODE_SIGNING_ALLOWED=NO \
    THEOS_PACKAGE_SCHEME=roothide \
    THEOS_PACKAGE_INSTALL_PREFIX= \
    ARCHS=arm64e \
    MonkeyDevInstallOnAnyBuild=NO \
    MonkeyDevBuildPackageOnAnyBuild=NO
else
  echo "[3/10] Skip native roothide xcodebuild."
fi

if [ ! -d "$ROOTFUL_APP" ] || [ ! -d "$ROOTLESS_APP" ]; then
    echo "[ERR] Build output app not found." >&2
    exit 1
fi

if [ "$BUILD_NATIVE_ROOTHIDE" = "1" ] && [ ! -d "$ROOTHIDE_APP" ]; then
    echo "[ERR] Native roothide build output app not found: $ROOTHIDE_APP" >&2
    exit 1
fi

echo "[4/10] Strip app binaries..."
strip_app "$ROOTFUL_APP"
strip_app "$ROOTLESS_APP"
if [ "$BUILD_NATIVE_ROOTHIDE" = "1" ]; then
  strip_app "$ROOTHIDE_APP"
fi

echo "[5/10] Sign app binaries..."
sign_app "$ROOTFUL_APP" "$APP_ENT_JB"
sign_app "$ROOTLESS_APP" "$APP_ENT_JB"
if [ "$BUILD_NATIVE_ROOTHIDE" = "1" ]; then
  sign_roothide_app "$ROOTHIDE_APP"
fi

echo "[5b/10] Build companion tweak dylibs..."
TWEAK_STAGE_DIR="$STAGE_DIR/tweak"
mkdir -p "$TWEAK_STAGE_DIR"
build_tweak_dylib arm64 "$TWEAK_STAGE_DIR/$TWEAK_NAME.dylib"
if [ "$BUILD_NATIVE_ROOTHIDE" = "1" ]; then
  build_tweak_dylib arm64e "$TWEAK_STAGE_DIR/$TWEAK_NAME-arm64e.dylib"
fi

# v3.0 deb Settings-only: build the PreferenceBundle with Theos (not Xcode:
# Preferences.framework headers are not in the app target). Fail fast if the
# bundle cannot be built, so a deb never ships with no UI at all.
# Set CHARGEGUARD_ALLOW_SETTINGS_PLIST_ONLY=1 only for local debugging; never for release.
stage_settings_bundle() {
  dest_dir="$1"
  built_bundle=""
  if [ -d "$ROOT_DIR/ChargeLimiter/ChargeGuardSettings" ]; then
    if [ -n "${THEOS:-}" ] || [ -d /opt/theos ]; then
      (cd "$ROOT_DIR/ChargeLimiter/ChargeGuardSettings" && THEOS="${THEOS:-/opt/theos}" make -s 2>/dev/null || true)
      built_bundle="$(find "$ROOT_DIR/ChargeLimiter/ChargeGuardSettings/.theos" -maxdepth 4 -type d -name 'ChargeGuardSettings.bundle' 2>/dev/null | head -n 1 || true)"
    fi
  fi
  mkdir -p "$dest_dir"
  if [ -n "$built_bundle" ] && [ -d "$built_bundle" ]; then
    cp -a "$built_bundle" "$dest_dir/ChargeGuardSettings.bundle"
    return 0
  fi
  if [ "${CHARGEGUARD_ALLOW_SETTINGS_PLIST_ONLY:-0}" = "1" ]; then
    echo "[WARN] Settings bundle binary not built; staging plist-only bundle for debugging only." >&2
    mkdir -p "$dest_dir/ChargeGuardSettings.bundle"
    cp -p "$ROOT_DIR/ChargeLimiter/ChargeGuardSettings/Root.plist" "$dest_dir/ChargeGuardSettings.bundle/Root.plist"
    cp -p "$ROOT_DIR/ChargeLimiter/ChargeGuardSettings/Info.plist" "$dest_dir/ChargeGuardSettings.bundle/Info.plist"
    return 0
  fi
  echo "[ERR] ChargeGuardSettings.bundle could not be built (Theos + Preferences headers required)." >&2
  echo "[ERR] Build it with: cd ChargeLimiter/ChargeGuardSettings && make THEOS=/opt/theos" >&2
  exit 1
}

# Overnight fix: the Settings bundle alone is not a Settings entry.
# Root.plist is the page shown AFTER tapping an entry; PreferenceLoader
# needs a Preferences/ChargeGuard.plist entry to show ChargeGuard in the
# Settings list at all. Without this, the Settings-only deb would ship
# with no UI. Stage it with the same prefix as the bundle per variant.
stage_settings_entry() {
  dest_dir="$1"
  mkdir -p "$dest_dir"
  cp -p "$ROOT_DIR/ChargeLimiter/ChargeGuardSettings/ChargeGuard.plist" "$dest_dir/ChargeGuard.plist"
}

echo "[6/10] Prepare package trees..."
cp -a "$PKG_ROOTFUL_DIR" "$STAGE_ROOTFUL_DIR"
cp -a "$PKG_ROOTLESS_DIR" "$STAGE_ROOTLESS_DIR"
[ -d "$STAGE_ROOTFUL_DIR/DEBIAN" ] || {
  echo "[ERR] Missing rootful package template: $STAGE_ROOTFUL_DIR/DEBIAN" >&2
  exit 1
}
[ -d "$STAGE_ROOTLESS_DIR/DEBIAN" ] || {
  echo "[ERR] Missing rootless package template: $STAGE_ROOTLESS_DIR/DEBIAN" >&2
  exit 1
}
# v3.0 deb Settings-only: deb packages must NOT contain any .app.
# Daemon binary -> /usr/libexec; Settings bundle -> PreferenceBundles.
# The .app is still built and used only for the TrollStore tipa below.
rm -rf "$STAGE_ROOTFUL_DIR/Applications"
rm -rf "$STAGE_ROOTLESS_DIR/Applications"
rm -rf "$STAGE_ROOTLESS_DIR/var/jb/Applications"
mkdir -p "$STAGE_ROOTFUL_DIR/usr/libexec" "$STAGE_ROOTLESS_DIR/var/jb/usr/libexec"
cp -p "$ROOTFUL_APP/ChargeGuardDaemon" "$STAGE_ROOTFUL_DIR/usr/libexec/ChargeGuardDaemon"
cp -p "$ROOTLESS_APP/ChargeGuardDaemon" "$STAGE_ROOTLESS_DIR/var/jb/usr/libexec/ChargeGuardDaemon"
chmod 755 "$STAGE_ROOTFUL_DIR/usr/libexec/ChargeGuardDaemon" "$STAGE_ROOTLESS_DIR/var/jb/usr/libexec/ChargeGuardDaemon"
stage_settings_bundle "$STAGE_ROOTFUL_DIR/Library/PreferenceBundles"
stage_settings_entry "$STAGE_ROOTFUL_DIR/Library/PreferenceLoader/Preferences"
stage_settings_bundle "$STAGE_ROOTLESS_DIR/var/jb/Library/PreferenceBundles"
stage_settings_entry "$STAGE_ROOTLESS_DIR/var/jb/Library/PreferenceLoader/Preferences"

stage_tweak_files "$STAGE_ROOTFUL_DIR" "$TWEAK_STAGE_DIR/$TWEAK_NAME.dylib"
stage_tweak_files "$STAGE_ROOTLESS_DIR/var/jb" "$TWEAK_STAGE_DIR/$TWEAK_NAME.dylib"

clean_host_metadata "$STAGE_ROOTFUL_DIR"
clean_host_metadata "$STAGE_ROOTLESS_DIR"
chmod 755 "$STAGE_ROOTFUL_DIR/DEBIAN" "$STAGE_ROOTLESS_DIR/DEBIAN"
chmod 755 "$STAGE_ROOTFUL_DIR/DEBIAN"/* "$STAGE_ROOTLESS_DIR/DEBIAN"/*
set_control_version "$STAGE_ROOTFUL_DIR/DEBIAN/control"
set_control_version "$STAGE_ROOTLESS_DIR/DEBIAN/control"

if [ "$BUILD_NATIVE_ROOTHIDE" = "1" ]; then
  echo "[7/10] Stage native Package_roothide..."
  [ -d "$PKG_ROOTHIDE_DIR/DEBIAN" ] || {
    echo "[ERR] Missing native Package_roothide template: $PKG_ROOTHIDE_DIR/DEBIAN" >&2
    exit 1
  }
  cp -a "$PKG_ROOTHIDE_DIR" "$STAGE_ROOTHIDE_DIR"
  # Rootful and roothide share these byte-identical files; keep one canonical source.
  cp -p "$PKG_ROOTFUL_DIR/DEBIAN/postrm" "$STAGE_ROOTHIDE_DIR/DEBIAN/postrm"
  chmod 755 "$STAGE_ROOTHIDE_DIR/DEBIAN/postrm"
  mkdir -p "$STAGE_ROOTHIDE_DIR/Library/LaunchDaemons"
  cp -p "$PKG_ROOTFUL_DIR/Library/LaunchDaemons/com.chargeguard.plist" \
    "$STAGE_ROOTHIDE_DIR/Library/LaunchDaemons/com.chargeguard.plist"
  chmod 644 "$STAGE_ROOTHIDE_DIR/Library/LaunchDaemons/com.chargeguard.plist"
  # v3.0 deb Settings-only (roothide stage is jbroot-relative).
  rm -rf "$STAGE_ROOTHIDE_DIR/Applications"
  mkdir -p "$STAGE_ROOTHIDE_DIR/usr/libexec"
  cp -p "$ROOTHIDE_APP/ChargeGuardDaemon" "$STAGE_ROOTHIDE_DIR/usr/libexec/ChargeGuardDaemon"
  chmod 755 "$STAGE_ROOTHIDE_DIR/usr/libexec/ChargeGuardDaemon"
  stage_settings_bundle "$STAGE_ROOTHIDE_DIR/Library/PreferenceBundles"
stage_settings_entry "$STAGE_ROOTHIDE_DIR/Library/PreferenceLoader/Preferences"
  stage_tweak_files "$STAGE_ROOTHIDE_DIR" "$TWEAK_STAGE_DIR/$TWEAK_NAME-arm64e.dylib"
  clean_host_metadata "$STAGE_ROOTHIDE_DIR"
  chmod 755 "$STAGE_ROOTHIDE_DIR/DEBIAN"
  chmod 755 "$STAGE_ROOTHIDE_DIR/DEBIAN"/*
  set_control_version "$STAGE_ROOTHIDE_DIR/DEBIAN/control"
  set_roothide_control_arch "$STAGE_ROOTHIDE_DIR/DEBIAN/control"
else
  echo "[7/10] Skip roothide package by request."
fi

echo "[8/10] Build TrollStore package..."
cp -a "$ROOTLESS_APP" "$PAYLOAD_DIR/ChargeGuard.app"
sign_app "$PAYLOAD_DIR/ChargeGuard.app" "$APP_ENT_TS"
clean_host_metadata "$PAYLOAD_DIR"
(
  cd "$ROOT_DIR"
  rm -f "$TIPA_OUT"
  zip -r "$TIPA_OUT" Payload >/dev/null
)
rm -rf "$PAYLOAD_DIR"

echo "[9/10] Build deb packages..."
rm -f "$ROOTFUL_DEB_OUT" "$ROOTLESS_DEB_OUT" "$ROOTHIDE_DEB_OUT"
dpkg_build_package "$STAGE_ROOTFUL_DIR" "$ROOTFUL_DEB_OUT"
dpkg_build_package "$STAGE_ROOTLESS_DIR" "$ROOTLESS_DEB_OUT"
if [ "$BUILD_ANY_ROOTHIDE" = "1" ]; then
  dpkg_build_package "$STAGE_ROOTHIDE_DIR" "$ROOTHIDE_DEB_OUT"
fi

extract_arch() {
  xcrun lipo -info "$1" | sed -n 's/.*architecture: \(.*\)$/\1/p'
}

check_binary() {
  BIN_PATH="$1"
  EXPECTED_ARCH="$2"
  BUNDLE_ID="$3"

  [ -f "$BIN_PATH" ] || {
    echo "[ERR] Missing binary: $BIN_PATH" >&2
    exit 1
  }

  if ! ENT="$(ldid -e "$BIN_PATH" 2>/dev/null)"; then
    echo "[ERR] Failed to extract entitlements: $BIN_PATH" >&2
    exit 1
  fi

  echo "$ENT" | rg -F -q "<string>$BUNDLE_ID</string>" || {
    echo "[ERR] application-identifier mismatch in $BIN_PATH" >&2
    exit 1
  }

  echo "$ENT" | rg -q "$TROLLSTORE_BANNED_ENTITLEMENTS_REGEX" && {
    echo "[ERR] Found TrollStore banned entitlement in $BIN_PATH" >&2
    exit 1
  }

  ARCH="$(extract_arch "$BIN_PATH")"
  if [ "$ARCH" != "$EXPECTED_ARCH" ]; then
    echo "[ERR] Arch mismatch: expected $EXPECTED_ARCH, got $ARCH ($BIN_PATH)" >&2
    exit 1
  fi
}

check_app() {
  APP_PATH="$1"
  EXPECTED_ARCH="$2"

  BID="$(plutil -extract CFBundleIdentifier raw -o - "$APP_PATH/Info.plist")"
  if [ "$BID" != "com.chargeguard" ]; then
    echo "[ERR] Unexpected bundle id: $BID ($APP_PATH)" >&2
    exit 1
  fi

  check_binary "$APP_PATH/ChargeGuard" "$EXPECTED_ARCH" "$BID"
  check_binary "$APP_PATH/ChargeGuardDaemon" "$EXPECTED_ARCH" "$BID"
}

check_deb_field() {
  deb_path="$1"
  field="$2"
  expected="$3"

  actual="$(dpkg-deb -f "$deb_path" "$field")"
  if [ "$actual" != "$expected" ]; then
    echo "[ERR] Unexpected $field in $deb_path: expected $expected, got $actual" >&2
    exit 1
  fi
}

check_no_host_metadata() {
  stage_path="$1"
  if find "$stage_path" \( -name .DS_Store -o -name __MACOSX -o -name '._*' \) | rg -q .; then
    echo "[ERR] Host metadata found in package stage: $stage_path" >&2
    find "$stage_path" \( -name .DS_Store -o -name __MACOSX -o -name '._*' \) >&2
    exit 1
  fi
}

check_deb_metadata() {
  deb_path="$1"
  expected_arch="$2"

  [ -f "$deb_path" ] || {
    echo "[ERR] Missing package output: $deb_path" >&2
    exit 1
  }

  check_deb_field "$deb_path" Package "com.chargeguard"
  check_deb_field "$deb_path" Version "$VERSION"
  check_deb_field "$deb_path" Architecture "$expected_arch"
}

check_tweak_files() {
  lib_root="$1"
  expected_tweak_arch="$2"
  tweak_dylib="$lib_root/Library/MobileSubstrate/DynamicLibraries/CLThermalSim.dylib"
  tweak_plist="$lib_root/Library/MobileSubstrate/DynamicLibraries/CLThermalSim.plist"
  [ -f "$tweak_dylib" ] || {
    echo "[ERR] Missing companion tweak dylib: $tweak_dylib" >&2
    exit 1
  }
  [ -f "$tweak_plist" ] || {
    echo "[ERR] Missing companion tweak filter plist: $tweak_plist" >&2
    exit 1
  }
  TWEAK_ARCH="$(xcrun lipo -info "$tweak_dylib" | sed -n 's/.*architecture: \(.*\)$/\1/p')"
  if [ "$TWEAK_ARCH" != "$expected_tweak_arch" ]; then
    echo "[ERR] Unexpected companion tweak architecture: $TWEAK_ARCH (expected $expected_tweak_arch)" >&2
    exit 1
  fi
}

check_rootful_stage() {
  stage_path="$1"
  daemon_path="$stage_path/usr/libexec/ChargeGuardDaemon"
  bundle_path="$stage_path/Library/PreferenceBundles/ChargeGuardSettings.bundle"
  plist_path="$stage_path/Library/LaunchDaemons/com.chargeguard.plist"

  # v3.0 deb Settings-only: no .app anywhere in the deb stage.
  [ ! -e "$stage_path/Applications" ] || {
    echo "[ERR] Rootful deb stage must not contain Applications (deb is Settings-only): $stage_path/Applications" >&2
    exit 1
  }
  [ -f "$daemon_path" ] || {
    echo "[ERR] Missing rootful daemon binary: $daemon_path" >&2
    exit 1
  }
  [ -f "$bundle_path/Root.plist" ] || {
    echo "[ERR] Missing rootful Settings bundle: $bundle_path" >&2
    exit 1
  }
  [ -f "$stage_path/Library/PreferenceLoader/Preferences/ChargeGuard.plist" ] || {
    echo "[ERR] Missing rootful PreferenceLoader entry: $stage_path/Library/PreferenceLoader/Preferences/ChargeGuard.plist" >&2
    exit 1
  }
  [ -f "$plist_path" ] || {
    echo "[ERR] Missing rootful launch daemon plist: $plist_path" >&2
    exit 1
  }
  PLIST_PROGRAM="$(plutil -extract Program raw -o - "$plist_path")"
  if [ "$PLIST_PROGRAM" != "/usr/libexec/ChargeGuardDaemon" ]; then
    echo "[ERR] Unexpected rootful launch daemon program path: $PLIST_PROGRAM" >&2
    exit 1
  fi
  [ ! -e "$stage_path/var/jb" ] || {
    echo "[ERR] Rootful package stage contains rootless install root: $stage_path/var/jb" >&2
    exit 1
  }
  check_no_host_metadata "$stage_path"
  check_binary "$daemon_path" "arm64" "com.chargeguard"
  check_tweak_files "$stage_path" "arm64"
}

check_rootless_stage() {
  stage_path="$1"
  daemon_path="$stage_path/var/jb/usr/libexec/ChargeGuardDaemon"
  bundle_path="$stage_path/var/jb/Library/PreferenceBundles/ChargeGuardSettings.bundle"
  plist_path="$stage_path/var/jb/Library/LaunchDaemons/com.chargeguard.plist"

  # v3.0 deb Settings-only: no .app anywhere in the deb stage.
  [ ! -e "$stage_path/var/jb/Applications" ] || {
    echo "[ERR] Rootless deb stage must not contain Applications (deb is Settings-only)." >&2
    exit 1
  }
  [ -f "$daemon_path" ] || {
    echo "[ERR] Missing rootless daemon binary: $daemon_path" >&2
    exit 1
  }
  [ -f "$bundle_path/Root.plist" ] || {
    echo "[ERR] Missing rootless Settings bundle: $bundle_path" >&2
    exit 1
  }
  [ -f "$stage_path/var/jb/Library/PreferenceLoader/Preferences/ChargeGuard.plist" ] || {
    echo "[ERR] Missing rootless PreferenceLoader entry." >&2
    exit 1
  }
  [ -f "$plist_path" ] || {
    echo "[ERR] Missing rootless launch daemon plist: $plist_path" >&2
    exit 1
  }
  PLIST_PROGRAM="$(plutil -extract Program raw -o - "$plist_path")"
  if [ "$PLIST_PROGRAM" != "/var/jb/usr/libexec/ChargeGuardDaemon" ]; then
    echo "[ERR] Unexpected rootless launch daemon program path: $PLIST_PROGRAM" >&2
    exit 1
  fi
  [ ! -e "$stage_path/Applications" ] || {
    echo "[ERR] Rootless package stage contains rootful app path." >&2
    exit 1
  }
  check_no_host_metadata "$stage_path"
  check_binary "$daemon_path" "arm64" "com.chargeguard"
  check_tweak_files "$stage_path/var/jb" "arm64"
}

check_roothide_stage() {
  STAGE_PATH="$1"
  # v3.0 deb Settings-only: roothide stage has no .app; daemon in usr/libexec.
  DAEMON_PATH="$STAGE_PATH/usr/libexec/ChargeGuardDaemon"
  BUNDLE_PATH="$STAGE_PATH/Library/PreferenceBundles/ChargeGuardSettings.bundle"
  PLIST_PATH="$STAGE_PATH/Library/LaunchDaemons/com.chargeguard.plist"
  POSTINST_PATH="$STAGE_PATH/DEBIAN/postinst"
  PRERM_PATH="$STAGE_PATH/DEBIAN/prerm"
  POSTRM_PATH="$STAGE_PATH/DEBIAN/postrm"

  [ ! -e "$STAGE_PATH/Applications" ] || {
    echo "[ERR] Roothide deb stage must not contain Applications (deb is Settings-only)." >&2
    exit 1
  }

  [ -f "$DAEMON_PATH" ] || {
    echo "[ERR] Missing roothide daemon binary: $DAEMON_PATH" >&2
    exit 1
  }

  [ -f "$BUNDLE_PATH/Root.plist" ] || {
    echo "[ERR] Missing roothide Settings bundle: $BUNDLE_PATH" >&2
    exit 1
  }

  [ -f "$STAGE_PATH/Library/PreferenceLoader/Preferences/ChargeGuard.plist" ] || {
    echo "[ERR] Missing roothide PreferenceLoader entry." >&2
    exit 1
  }

  [ -f "$PLIST_PATH" ] || {
    echo "[ERR] Missing roothide launch daemon plist: $PLIST_PATH" >&2
    exit 1
  }

  [ ! -e "$STAGE_PATH/var/jb" ] || {
    echo "[ERR] Found unexpected rootless install root in roothide stage." >&2
    exit 1
  }

  CONTROL_ARCH="$(awk -F': ' '/^Architecture:/{print $2; exit}' "$STAGE_PATH/DEBIAN/control")"
  if [ "$CONTROL_ARCH" != "iphoneos-arm64e" ]; then
    echo "[ERR] Unexpected roothide control architecture: $CONTROL_ARCH" >&2
    exit 1
  fi

  PLIST_PROGRAM="$(plutil -extract Program raw -o - "$PLIST_PATH")"
  if [ "$PLIST_PROGRAM" != "/usr/libexec/ChargeGuardDaemon" ]; then
    echo "[ERR] Unexpected roothide launch daemon program path: $PLIST_PROGRAM" >&2
    exit 1
  fi

  rg -F -q 'DAEMON_BIN="/usr/libexec/ChargeGuardDaemon"' "$POSTINST_PATH" || {
    echo "[ERR] roothide postinst DAEMON_BIN is not the v3.0 libexec path." >&2
    exit 1
  }

  rg -F -q 'DAEMON_PLIST="/Library/LaunchDaemons/com.chargeguard.plist"' "$POSTINST_PATH" || {
    echo "[ERR] roothide postinst DAEMON_PLIST is not the v3.0 path." >&2
    exit 1
  }

  rg -F -q 'DAEMON_BIN="/usr/libexec/ChargeGuardDaemon"' "$PRERM_PATH" || {
    echo "[ERR] roothide prerm DAEMON_BIN is not the v3.0 libexec path." >&2
    exit 1
  }

  rg -F -q 'DAEMON_PLIST="/Library/LaunchDaemons/com.chargeguard.plist"' "$PRERM_PATH" || {
    echo "[ERR] roothide prerm DAEMON_PLIST is not the v3.0 path." >&2
    exit 1
  }

  rg -F -q 'APP_DIR' "$POSTRM_PATH" && {
    echo "[ERR] roothide postrm must not reference APP_DIR in v3.0 (no .app in deb)." >&2
    exit 1
  } || true

  # Native roothide scheme builds arm64e (matches Relaxin roothide device slice
  # and the iphoneos-arm64e dpkg architecture label in DEBIAN/control).
  # v3.0 deb stage has no .app: check the daemon binary directly instead.
  check_binary "$DAEMON_PATH" "arm64e" "com.chargeguard"

  # Link-path guard: residual /var/jb load commands are never valid in roothide stage.
  # Rootful-shaped native binaries that only link system libs (no jb paths) are OK.
  for bin_name in ChargeGuardDaemon; do
    bin_path="$DAEMON_PATH"
    [ -f "$bin_path" ] || {
      echo "[ERR] Missing roothide binary for link check: $bin_path" >&2
      exit 1
    }
    if xcrun otool -L "$bin_path" 2>/dev/null | awk 'NR > 1 { print $1 }' | rg -F -q '/var/jb'; then
      echo "[ERR] Residual /var/jb load path in roothide binary: $bin_path" >&2
      xcrun otool -L "$bin_path" >&2 || true
      exit 1
    fi
    if list_rpaths "$bin_path" 2>/dev/null | rg -F -q '/var/jb'; then
      echo "[ERR] Residual /var/jb rpath in roothide binary: $bin_path" >&2
      list_rpaths "$bin_path" >&2 || true
      exit 1
    fi
  done
  check_tweak_files "$STAGE_PATH" "arm64e"
}
echo "[10/10] Verify package contents..."
check_rootful_stage "$STAGE_ROOTFUL_DIR"
check_rootless_stage "$STAGE_ROOTLESS_DIR"
check_deb_metadata "$ROOTFUL_DEB_OUT" "iphoneos-arm"
check_deb_metadata "$ROOTLESS_DEB_OUT" "iphoneos-arm64"
if [ "$BUILD_ANY_ROOTHIDE" = "1" ]; then
  check_roothide_stage "$STAGE_ROOTHIDE_DIR"
  check_no_host_metadata "$STAGE_ROOTHIDE_DIR"
  check_deb_metadata "$ROOTHIDE_DEB_OUT" "iphoneos-arm64e"
fi

echo "[OK] Done"
echo "[OUT] $TIPA_OUT"
echo "[OUT] $ROOTFUL_DEB_OUT"
echo "[OUT] $ROOTLESS_DEB_OUT"
if [ "$BUILD_NATIVE_ROOTHIDE" = "1" ]; then
  echo "[OUT] $ROOTHIDE_DEB_OUT"
  echo "[INFO] roothide package was built natively via scheme \"ChargeGuard roothide\" and Package_roothide."
else
  echo "[INFO] roothide package was skipped."
fi
