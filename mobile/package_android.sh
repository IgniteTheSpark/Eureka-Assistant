#!/bin/bash
#
# Ureka Android 打包脚本。
#
# 常用命令：
#   ./package_android.sh publish=1 api_base=http://39.96.55.118 des="发版包"
#   ./package_android.sh type=release action=build api_base=http://39.96.55.118
#   ./package_android.sh type=debug action=install api_base=http://localhost:8000
#
# 参数说明：
#   publish=0|1
#     0：普通模式，按显式传入的参数执行。
#     1：发布快捷模式，强制设置 action=upload、type=release、
#        package_type=apk, arm=v8a, clean=3, notify=on.
#     用于发布正式测试包或发版包到蒲公英。
#
#   action=build|upload|install
#     build：只构建并复制产物。
#     upload：构建后上传 APK 到蒲公英，并按配置发送钉钉通知。
#     install：构建 APK 并安装到第一台已连接的 Android 设备。
#     publish=1 会覆盖为 upload。
#
#   type=debug|profile|release
#     Flutter 构建模式。release 需要 .tokens/android_signing.properties。
#
#   package_type=apk|aab
#     apk：按 ABI 拆分 APK；蒲公英上传和设备安装必须使用 APK。
#     aab：只构建 App Bundle；当前脚本不会上传 AAB。
#
#   arm=v8a|v7a|x86
#     package_type=apk 时选择要复制/上传的拆分包。
#     v8a 对应 arm64-v8a，是默认发布目标。
#
#   clean=0|3
#     0：增量构建。
#     3：构建前执行 flutter clean && flutter pub get。
#     publish=1 会覆盖为 3。
#
#   api_base=<url>
#     注入 --dart-define=API_BASE=<url>。不传时读取
#     .tokens/build.json 的 api_base，仍为空则回退到 http://localhost:8000。
#
#   des=<text>
#     蒲公英更新说明和钉钉通知描述。
#
#   at=all|phone1,phone2|dingtalk:id
#     钉钉提醒对象。不传时 ding_notify.py 使用
#     .tokens/dingding.json 的 default_at。
#
#   notify=on|off
#     蒲公英上传成功后是否发送钉钉通知。
#
#   build_name=<version>, build_number=<number>
#     可选 Flutter 版本覆盖值；传入时追加 --build-name 和 --build-number。
#
# 本地配置：
#   .tokens/pgyer.json                 仅 action=upload 时使用。
#   .tokens/dingding.json              上传成功且 notify=on 时使用。
#   .tokens/android_signing.properties type=release 时必需。
#   .tokens/build.json                 可选默认值，例如 api_base。

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
    *) echo "警告：忽略未知参数：$arg" ;;
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

[[ "$PUBLISH" =~ ^[0-9]+$ ]] || { echo "错误：publish 必须是数字"; exit 1; }
[[ "$ACTION" =~ ^(build|upload|install)$ ]] || { echo "错误：action 必须是 build、upload 或 install"; exit 1; }
[[ "$BUILD_TYPE" =~ ^(debug|profile|release)$ ]] || { echo "错误：type 必须是 debug、profile 或 release"; exit 1; }
[[ "$ARM" =~ ^(v8a|v7a|x86)$ ]] || { echo "错误：arm 必须是 v8a、v7a 或 x86"; exit 1; }
[[ "$PACKAGE_TYPE" =~ ^(apk|aab)$ ]] || { echo "错误：package_type 必须是 apk 或 aab"; exit 1; }
[[ "$CLEAN_STEPS" =~ ^(0|3)$ ]] || { echo "错误：clean 必须是 0 或 3"; exit 1; }
[[ "$NOTIFY" =~ ^(on|off)$ ]] || { echo "错误：notify 必须是 on 或 off"; exit 1; }

if [ "$ACTION" = "install" ] && [ "$PACKAGE_TYPE" != "apk" ]; then
  echo "错误：action=install 仅支持 package_type=apk"
  exit 1
fi

if [ "$ACTION" = "upload" ] && [ "$PACKAGE_TYPE" != "apk" ]; then
  echo "错误：蒲公英上传仅支持 Android APK，请使用 package_type=apk"
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
  [ -f "$ANDROID_SIGNING_CONFIG" ] || { echo "错误：缺少 Android 签名配置：$ANDROID_SIGNING_CONFIG"; exit 1; }
  STORE_FILE="$(properties_value "$ANDROID_SIGNING_CONFIG" "storeFile")"
  STORE_PASSWORD="$(properties_value "$ANDROID_SIGNING_CONFIG" "storePassword")"
  KEY_ALIAS="$(properties_value "$ANDROID_SIGNING_CONFIG" "keyAlias")"
  KEY_PASSWORD="$(properties_value "$ANDROID_SIGNING_CONFIG" "keyPassword")"
  [ -n "$STORE_FILE" ] || { echo "错误：android_signing.properties 缺少 storeFile"; exit 1; }
  [ -n "$STORE_PASSWORD" ] || { echo "错误：android_signing.properties 缺少 storePassword"; exit 1; }
  [ -n "$KEY_ALIAS" ] || { echo "错误：android_signing.properties 缺少 keyAlias"; exit 1; }
  [ -n "$KEY_PASSWORD" ] || { echo "错误：android_signing.properties 缺少 keyPassword"; exit 1; }
  if [[ "$STORE_FILE" = /* ]]; then
    RESOLVED_STORE_FILE="$STORE_FILE"
  else
    RESOLVED_STORE_FILE="$PROJECT_ROOT/$STORE_FILE"
  fi
  [ -f "$RESOLVED_STORE_FILE" ] || { echo "错误：未找到 Android 签名文件：$RESOLVED_STORE_FILE"; exit 1; }
fi

VERSION="$(grep '^version:' pubspec.yaml | sed 's/version:[[:space:]]*//' | tr -d ' ')"
[ -n "$VERSION" ] || { echo "错误：无法从 pubspec.yaml 读取版本号"; exit 1; }
TIMESTAMP="$(date +'%Y-%m-%d-%H-%M-%S')"

echo "=========================================="
echo "Ureka Android 打包"
echo "  发布模式      : $PUBLISH"
echo "  动作          : $ACTION"
echo "  构建类型      : $BUILD_TYPE"
echo "  产物类型      : $PACKAGE_TYPE"
echo "  架构          : $ARM"
echo "  清理步骤      : $CLEAN_STEPS"
echo "  API 地址      : $API_BASE"
echo "  版本          : $VERSION"
echo "  钉钉通知      : $NOTIFY"
echo "  描述          : $DES"
echo "=========================================="

if [ "$CLEAN_STEPS" = "3" ]; then
  echo "步骤 1：执行 flutter clean && flutter pub get"
  flutter clean
  flutter pub get
else
  echo "步骤 1：跳过清理"
fi

echo "步骤 2：构建产物"
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

[ -f "$SOURCE_FILE" ] || { echo "错误：未找到构建产物：$SOURCE_FILE"; exit 1; }

ARTIFACT_FILE="$OUTPUT_DIR/ureka-android-${BUILD_TYPE}-${TARGET_LABEL}-${VERSION}-${TIMESTAMP}.${EXT}"
cp "$SOURCE_FILE" "$ARTIFACT_FILE"
mkdir -p "$ROOT_OUTPUT_DIR"
BACKUP_FILE="$ROOT_OUTPUT_DIR/$(basename "$ARTIFACT_FILE")"
cp "$ARTIFACT_FILE" "$BACKUP_FILE"

echo "步骤 3：产物已准备"
echo "  路径：$ARTIFACT_FILE"
echo "  备份：$BACKUP_FILE"
echo "  大小：$(du -h "$ARTIFACT_FILE" | cut -f1)"

if [ "$ACTION" = "install" ]; then
  echo "步骤 4：安装 APK"
  command -v adb >/dev/null 2>&1 || { echo "错误：未找到 adb"; exit 1; }
  DEVICE_ID="$(adb devices | awk 'NR > 1 && $2 == "device" {print $1; exit}')"
  [ -n "$DEVICE_ID" ] || { echo "错误：未检测到 Android 设备"; exit 1; }
  adb -s "$DEVICE_ID" install -d -r "$ARTIFACT_FILE"
  adb -s "$DEVICE_ID" shell monkey -p "com.eureka.mindapp" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
fi

if [ "$ACTION" = "upload" ]; then
  echo "步骤 4：上传蒲公英"
  [ -f "$PGYER_CONFIG" ] || { echo "错误：缺少蒲公英配置：$PGYER_CONFIG"; exit 1; }
  API_KEY="$(json_value "$PGYER_CONFIG" "api_key" "")"
  INSTALL_TYPE="$(json_value "$PGYER_CONFIG" "install_type" "2")"
  INSTALL_PASSWORD="$(json_value "$PGYER_CONFIG" "install_password" "1324")"
  CHANNEL_SHORTCUT="$(json_value "$PGYER_CONFIG" "channel_shortcut" "")"
  [ -n "$API_KEY" ] || { echo "错误：.tokens/pgyer.json 缺少 api_key"; exit 1; }

  UPLOAD_CMD=("$PROJECT_ROOT/pgyer_upload.sh" "-k" "$API_KEY" "-t" "$INSTALL_TYPE" "-p" "$INSTALL_PASSWORD" "-d" "$DES" "-P" "-j")
  [ -n "$CHANNEL_SHORTCUT" ] && UPLOAD_CMD+=("-c" "$CHANNEL_SHORTCUT")
  UPLOAD_CMD+=("$ARTIFACT_FILE")

  set +e
  UPLOAD_OUTPUT="$("${UPLOAD_CMD[@]}" 2>&1)"
  UPLOAD_EXIT_CODE=$?
  set -e
  echo "$UPLOAD_OUTPUT"
  [ "$UPLOAD_EXIT_CODE" -eq 0 ] || { echo "错误：蒲公英上传失败"; exit "$UPLOAD_EXIT_CODE"; }

  DOWNLOAD_URL="$(echo "$UPLOAD_OUTPUT" | sed -n 's/^URL:[[:space:]]*//p' | tail -1)"
  [ -n "$DOWNLOAD_URL" ] || DOWNLOAD_URL="$(json_value "$PGYER_CONFIG" "android_fallback_url" "")"

  if [ "$NOTIFY" = "on" ]; then
    echo "步骤 5：发送钉钉通知"
    if [ ! -f "$DING_CONFIG" ]; then
      echo "警告：缺少钉钉配置：$DING_CONFIG"
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
      echo "  钉钉通知发送成功"
    else
      echo "警告：钉钉通知发送失败"
    fi
  fi
fi

echo "=========================================="
echo "完成：$ARTIFACT_FILE"
echo "=========================================="
