#!/bin/bash

set -euo pipefail

PUBLISH="0"
ACTION="build"
BUILD_TYPE="release"
ARM="v8a"
PACKAGE_TYPE="apk"
CLEAN_STEPS="0"
API_BASE=""
DES=""
AT=""
NOTIFY="on"
BUILD_NAME=""
BUILD_NUMBER=""

for arg in "$@"; do
  case "$arg" in
    publish=*) PUBLISH="${arg#publish=}" ;;
    action=*) ACTION="${arg#action=}" ;;
    type=*) BUILD_TYPE="${arg#type=}" ;;
    arm=*) ARM="${arg#arm=}" ;;
    package_type=*) PACKAGE_TYPE="${arg#package_type=}" ;;
    clean=*) CLEAN_STEPS="${arg#clean=}" ;;
    api_base=*) API_BASE="${arg#api_base=}" ;;
    des=*) DES="${arg#des=}" ;;
    at=*) AT="${arg#at=}" ;;
    notify=*) NOTIFY="${arg#notify=}" ;;
    build_name=*) BUILD_NAME="${arg#build_name=}" ;;
    build_number=*) BUILD_NUMBER="${arg#build_number=}" ;;
    *) echo "warning: unknown argument ignored: $arg" ;;
  esac
done

if [ "$PUBLISH" = "1" ]; then
  ACTION="upload"
  BUILD_TYPE="release"
  PACKAGE_TYPE="apk"
  ARM="v8a"
  CLEAN_STEPS="3"
  NOTIFY="on"
  [ -n "$DES" ] || DES="release package"
fi

[[ "$PUBLISH" =~ ^[0-9]+$ ]] || { echo "error: publish must be numeric"; exit 1; }
[[ "$ACTION" =~ ^(build|upload|install)$ ]] || { echo "error: action must be build, upload, or install"; exit 1; }
[[ "$BUILD_TYPE" =~ ^(debug|profile|release)$ ]] || { echo "error: type must be debug, profile, or release"; exit 1; }
[[ "$ARM" =~ ^(v8a|v7a|x86)$ ]] || { echo "error: arm must be v8a, v7a, or x86"; exit 1; }
[[ "$PACKAGE_TYPE" =~ ^(apk|aab)$ ]] || { echo "error: package_type must be apk or aab"; exit 1; }
[[ "$CLEAN_STEPS" =~ ^(0|3)$ ]] || { echo "error: clean must be 0 or 3"; exit 1; }
[[ "$NOTIFY" =~ ^(on|off)$ ]] || { echo "error: notify must be on or off"; exit 1; }

if [ "$ACTION" = "install" ] && [ "$PACKAGE_TYPE" != "apk" ]; then
  echo "error: action=install only supports package_type=apk"
  exit 1
fi

if [ "$ACTION" = "upload" ] && [ "$PACKAGE_TYPE" != "apk" ]; then
  echo "error: PGYER upload only supports Android APK; use package_type=apk"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
cd "$PROJECT_ROOT"

json_value() {
  python3 - "$1" "$2" "${3:-}" <<'PY'
import json
import sys

path, key, default = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    print(default)
    sys.exit(0)

value = data.get(key, default)
if value is None:
    value = default
print(value)
PY
}

BUILD_CONFIG="$PROJECT_ROOT/.tokens/build.json"
PGYER_CONFIG="$PROJECT_ROOT/.tokens/pgyer.json"
DING_CONFIG="$PROJECT_ROOT/.tokens/dingding.json"
ANDROID_SIGNING_CONFIG="$PROJECT_ROOT/.tokens/android_signing.properties"

if [ -z "$API_BASE" ]; then
  API_BASE="$(json_value "$BUILD_CONFIG" "api_base" "http://localhost:8000")"
fi

properties_value() {
  python3 - "$1" "$2" <<'PY'
import sys

path, key = sys.argv[1], sys.argv[2]
try:
    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            if k.strip() == key:
                print(v.strip())
                break
except FileNotFoundError:
    pass
PY
}

if [ "$BUILD_TYPE" = "release" ]; then
  [ -f "$ANDROID_SIGNING_CONFIG" ] || { echo "error: missing Android signing config: $ANDROID_SIGNING_CONFIG"; exit 1; }
  STORE_FILE="$(properties_value "$ANDROID_SIGNING_CONFIG" "storeFile")"
  STORE_PASSWORD="$(properties_value "$ANDROID_SIGNING_CONFIG" "storePassword")"
  KEY_ALIAS="$(properties_value "$ANDROID_SIGNING_CONFIG" "keyAlias")"
  KEY_PASSWORD="$(properties_value "$ANDROID_SIGNING_CONFIG" "keyPassword")"
  [ -n "$STORE_FILE" ] || { echo "error: android_signing.properties missing storeFile"; exit 1; }
  [ -n "$STORE_PASSWORD" ] || { echo "error: android_signing.properties missing storePassword"; exit 1; }
  [ -n "$KEY_ALIAS" ] || { echo "error: android_signing.properties missing keyAlias"; exit 1; }
  [ -n "$KEY_PASSWORD" ] || { echo "error: android_signing.properties missing keyPassword"; exit 1; }
  if [[ "$STORE_FILE" = /* ]]; then
    RESOLVED_STORE_FILE="$STORE_FILE"
  else
    RESOLVED_STORE_FILE="$PROJECT_ROOT/$STORE_FILE"
  fi
  [ -f "$RESOLVED_STORE_FILE" ] || { echo "error: Android signing storeFile not found: $RESOLVED_STORE_FILE"; exit 1; }
fi

VERSION="$(grep '^version:' pubspec.yaml | sed 's/version:[[:space:]]*//' | tr -d ' ')"
[ -n "$VERSION" ] || { echo "error: unable to read version from pubspec.yaml"; exit 1; }
TIMESTAMP="$(date +'%Y-%m-%d-%H-%M-%S')"

echo "=========================================="
echo "Ureka Android package"
echo "  publish      : $PUBLISH"
echo "  action       : $ACTION"
echo "  type         : $BUILD_TYPE"
echo "  package_type : $PACKAGE_TYPE"
echo "  arm          : $ARM"
echo "  clean        : $CLEAN_STEPS"
echo "  api_base     : $API_BASE"
echo "  version      : $VERSION"
echo "  notify       : $NOTIFY"
echo "  description  : $DES"
echo "=========================================="

if [ "$CLEAN_STEPS" = "3" ]; then
  echo "Step 1: flutter clean && flutter pub get"
  flutter clean
  flutter pub get
else
  echo "Step 1: skip clean"
fi

echo "Step 2: build artifact"
if [ "$PACKAGE_TYPE" = "apk" ]; then
  BUILD_CMD=("flutter" "build" "apk" "--split-per-abi")
else
  BUILD_CMD=("flutter" "build" "appbundle")
fi

case "$BUILD_TYPE" in
  debug) BUILD_CMD+=("--debug") ;;
  profile) BUILD_CMD+=("--profile") ;;
  release) BUILD_CMD+=("--release") ;;
esac

BUILD_CMD+=("--dart-define=API_BASE=${API_BASE}")
[ -n "$BUILD_NAME" ] && BUILD_CMD+=("--build-name=${BUILD_NAME}")
[ -n "$BUILD_NUMBER" ] && BUILD_CMD+=("--build-number=${BUILD_NUMBER}")

echo "  ${BUILD_CMD[*]}"
"${BUILD_CMD[@]}"

OUTPUT_DIR="build/app/outputs/package/$BUILD_TYPE"
mkdir -p "$OUTPUT_DIR"

if [ "$PACKAGE_TYPE" = "apk" ]; then
  case "$ARM" in
    v8a) APK_ABI="arm64-v8a" ;;
    v7a) APK_ABI="armeabi-v7a" ;;
    x86) APK_ABI="x86_64" ;;
  esac
  SOURCE_FILE="build/app/outputs/flutter-apk/app-${APK_ABI}-${BUILD_TYPE}.apk"
  EXT="apk"
  TARGET_LABEL="$ARM"
  ROOT_OUTPUT_DIR="$PROJECT_ROOT/apk_output"
else
  SOURCE_FILE="build/app/outputs/bundle/${BUILD_TYPE}/app-${BUILD_TYPE}.aab"
  EXT="aab"
  TARGET_LABEL="aab"
  ROOT_OUTPUT_DIR="$PROJECT_ROOT/aab_output"
fi

[ -f "$SOURCE_FILE" ] || { echo "error: artifact not found: $SOURCE_FILE"; exit 1; }

ARTIFACT_FILE="$OUTPUT_DIR/ureka-android-${BUILD_TYPE}-${TARGET_LABEL}-${VERSION}-${TIMESTAMP}.${EXT}"
cp "$SOURCE_FILE" "$ARTIFACT_FILE"
mkdir -p "$ROOT_OUTPUT_DIR"
BACKUP_FILE="$ROOT_OUTPUT_DIR/$(basename "$ARTIFACT_FILE")"
cp "$ARTIFACT_FILE" "$BACKUP_FILE"

echo "Step 3: artifact ready"
echo "  path: $ARTIFACT_FILE"
echo "  backup: $BACKUP_FILE"
echo "  size: $(du -h "$ARTIFACT_FILE" | cut -f1)"

if [ "$ACTION" = "install" ]; then
  echo "Step 4: install APK"
  command -v adb >/dev/null 2>&1 || { echo "error: adb not found"; exit 1; }
  DEVICE_ID="$(adb devices | awk 'NR > 1 && $2 == "device" {print $1; exit}')"
  [ -n "$DEVICE_ID" ] || { echo "error: no Android device found"; exit 1; }
  adb -s "$DEVICE_ID" install -d -r "$ARTIFACT_FILE"
  adb -s "$DEVICE_ID" shell monkey -p "com.eureka.eureka" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
fi

if [ "$ACTION" = "upload" ]; then
  echo "Step 4: upload to PGYER"
  [ -f "$PGYER_CONFIG" ] || { echo "error: missing PGYER config: $PGYER_CONFIG"; exit 1; }
  API_KEY="$(json_value "$PGYER_CONFIG" "api_key" "")"
  INSTALL_TYPE="$(json_value "$PGYER_CONFIG" "install_type" "2")"
  INSTALL_PASSWORD="$(json_value "$PGYER_CONFIG" "install_password" "1324")"
  CHANNEL_SHORTCUT="$(json_value "$PGYER_CONFIG" "channel_shortcut" "")"
  [ -n "$API_KEY" ] || { echo "error: .tokens/pgyer.json missing api_key"; exit 1; }

  UPLOAD_CMD=("$PROJECT_ROOT/pgyer_upload.sh" "-k" "$API_KEY" "-t" "$INSTALL_TYPE" "-p" "$INSTALL_PASSWORD" "-d" "$DES" "-P" "-j")
  [ -n "$CHANNEL_SHORTCUT" ] && UPLOAD_CMD+=("-c" "$CHANNEL_SHORTCUT")
  UPLOAD_CMD+=("$ARTIFACT_FILE")

  set +e
  UPLOAD_OUTPUT="$("${UPLOAD_CMD[@]}" 2>&1)"
  UPLOAD_EXIT_CODE=$?
  set -e
  echo "$UPLOAD_OUTPUT"
  [ "$UPLOAD_EXIT_CODE" -eq 0 ] || { echo "error: PGYER upload failed"; exit "$UPLOAD_EXIT_CODE"; }

  DOWNLOAD_URL="$(echo "$UPLOAD_OUTPUT" | sed -n 's/^URL:[[:space:]]*//p' | tail -1)"
  [ -n "$DOWNLOAD_URL" ] || DOWNLOAD_URL="$(json_value "$PGYER_CONFIG" "android_fallback_url" "")"

  if [ "$NOTIFY" = "on" ]; then
    echo "Step 5: send DingTalk notification"
    if [ ! -f "$DING_CONFIG" ]; then
      echo "warning: missing DingTalk config: $DING_CONFIG"
    elif python3 "$PROJECT_ROOT/ding_notify.py" \
      "android" \
      "$VERSION" \
      "$TIMESTAMP" \
      "$TARGET_LABEL" \
      "$BUILD_TYPE" \
      "$PACKAGE_TYPE" \
      "$API_BASE" \
      "$DES" \
      "$DOWNLOAD_URL" \
      "$INSTALL_PASSWORD" \
      "$AT"; then
      echo "  DingTalk notification sent"
    else
      echo "warning: DingTalk notification failed"
    fi
  fi
fi

echo "=========================================="
echo "Done: $ARTIFACT_FILE"
echo "=========================================="
