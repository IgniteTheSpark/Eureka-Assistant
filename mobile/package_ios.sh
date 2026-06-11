#!/bin/bash

set -euo pipefail

PUBLISH="0"
ACTION="build"
BUILD_TYPE="release"
EXPORT_METHOD="ad-hoc"
SCHEME="Runner"
CODESIGN="on"
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
    export_method=*) EXPORT_METHOD="${arg#export_method=}" ;;
    scheme=*) SCHEME="${arg#scheme=}" ;;
    codesign=*) CODESIGN="${arg#codesign=}" ;;
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
  EXPORT_METHOD="ad-hoc"
  CODESIGN="on"
  CLEAN_STEPS="3"
  NOTIFY="on"
  [ -n "$DES" ] || DES="release package"
fi

[[ "$PUBLISH" =~ ^[0-9]+$ ]] || { echo "error: publish must be numeric"; exit 1; }
[[ "$ACTION" =~ ^(build|upload)$ ]] || { echo "error: iOS action must be build or upload"; exit 1; }
[[ "$BUILD_TYPE" =~ ^(release)$ ]] || { echo "error: iOS type currently supports release only"; exit 1; }
[[ "$EXPORT_METHOD" =~ ^(ad-hoc|development|enterprise|app-store)$ ]] || { echo "error: invalid export_method"; exit 1; }
[[ "$CODESIGN" =~ ^(on|off)$ ]] || { echo "error: codesign must be on or off"; exit 1; }
[[ "$CLEAN_STEPS" =~ ^(0|3)$ ]] || { echo "error: clean must be 0 or 3"; exit 1; }
[[ "$NOTIFY" =~ ^(on|off)$ ]] || { echo "error: notify must be on or off"; exit 1; }

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

if [ -z "$API_BASE" ]; then
  API_BASE="$(json_value "$BUILD_CONFIG" "api_base" "http://localhost:8000")"
fi

VERSION="$(grep '^version:' pubspec.yaml | sed 's/version:[[:space:]]*//' | tr -d ' ')"
[ -n "$VERSION" ] || { echo "error: unable to read version from pubspec.yaml"; exit 1; }
TIMESTAMP="$(date +'%Y-%m-%d-%H-%M-%S')"

echo "=========================================="
echo "Ureka iOS package"
echo "  publish       : $PUBLISH"
echo "  action        : $ACTION"
echo "  type          : $BUILD_TYPE"
echo "  export_method : $EXPORT_METHOD"
echo "  scheme        : $SCHEME"
echo "  codesign      : $CODESIGN"
echo "  clean         : $CLEAN_STEPS"
echo "  api_base      : $API_BASE"
echo "  version       : $VERSION"
echo "  notify        : $NOTIFY"
echo "  description   : $DES"
echo "=========================================="

if [ "$CLEAN_STEPS" = "3" ]; then
  echo "Step 1: flutter clean && flutter pub get"
  flutter clean
  flutter pub get
else
  echo "Step 1: skip clean"
fi

echo "Step 2: build IPA"
BUILD_CMD=(
  "flutter" "build" "ipa"
  "--release"
  "--export-method=${EXPORT_METHOD}"
  "--dart-define=API_BASE=${API_BASE}"
)

if [ "$SCHEME" != "Runner" ]; then
  BUILD_CMD+=("--flavor=${SCHEME}")
fi
[ "$CODESIGN" = "off" ] && BUILD_CMD+=("--no-codesign")
[ -n "$BUILD_NAME" ] && BUILD_CMD+=("--build-name=${BUILD_NAME}")
[ -n "$BUILD_NUMBER" ] && BUILD_CMD+=("--build-number=${BUILD_NUMBER}")

echo "  ${BUILD_CMD[*]}"
"${BUILD_CMD[@]}"

SOURCE_IPA="$(find build/ios/ipa -maxdepth 1 -name '*.ipa' -print | sort | tail -1)"
[ -n "$SOURCE_IPA" ] && [ -f "$SOURCE_IPA" ] || { echo "error: no IPA found in build/ios/ipa"; exit 1; }

OUTPUT_DIR="build/ios/ipa_output"
ROOT_OUTPUT_DIR="$PROJECT_ROOT/ipa_output"
mkdir -p "$OUTPUT_DIR" "$ROOT_OUTPUT_DIR"

ARTIFACT_FILE="$OUTPUT_DIR/ureka-ios-${BUILD_TYPE}-${EXPORT_METHOD}-${VERSION}-${TIMESTAMP}.ipa"
cp "$SOURCE_IPA" "$ARTIFACT_FILE"
BACKUP_FILE="$ROOT_OUTPUT_DIR/$(basename "$ARTIFACT_FILE")"
cp "$ARTIFACT_FILE" "$BACKUP_FILE"

echo "Step 3: artifact ready"
echo "  path: $ARTIFACT_FILE"
echo "  backup: $BACKUP_FILE"
echo "  size: $(du -h "$ARTIFACT_FILE" | cut -f1)"

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
  [ -n "$DOWNLOAD_URL" ] || DOWNLOAD_URL="$(json_value "$PGYER_CONFIG" "ios_fallback_url" "")"

  if [ "$NOTIFY" = "on" ]; then
    echo "Step 5: send DingTalk notification"
    if [ ! -f "$DING_CONFIG" ]; then
      echo "warning: missing DingTalk config: $DING_CONFIG"
    elif python3 "$PROJECT_ROOT/ding_notify.py" \
      "ios" \
      "$VERSION" \
      "$TIMESTAMP" \
      "$EXPORT_METHOD" \
      "$BUILD_TYPE" \
      "ipa" \
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
