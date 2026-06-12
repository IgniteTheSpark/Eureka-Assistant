#!/bin/bash
#
# Ureka iOS 打包脚本。
#
# 常用命令：
#   ./package_ios.sh publish=1 api_base=http://39.96.55.118 des="发版包"
#   ./package_ios.sh action=build api_base=http://39.96.55.118
#   ./package_ios.sh action=upload export_method=ad-hoc des="iOS测试包"
#
# 参数说明：
#   publish=0|1
#     0：普通模式，按显式传入的参数执行。
#     1：发布快捷模式，强制设置 action=upload、type=release、
#        export_method=ad-hoc, codesign=on, clean=3, notify=on.
#     用于发布 ad-hoc IPA 到蒲公英。
#
#   action=build|upload
#     build：只构建并复制 IPA。
#     upload：构建后上传 IPA 到蒲公英，并按配置发送钉钉通知。
#     publish=1 会覆盖为 upload。
#
#   type=release
#     iOS 当前仅支持 release 打包。
#
#   export_method=ad-hoc|development|enterprise|app-store
#     传给 flutter build ipa --export-method。
#     ad-hoc 用于蒲公英或内部真机分发。
#     app-store 用于 App Store Connect，不用于蒲公英。
#
#   scheme=Runner
#     预留给后续 flavor/scheme；当前默认 Runner。
#     非 Runner 时会作为 --flavor 传入。
#
#   codesign=on|off
#     on：正常签名并导出 IPA。
#     off：追加 --no-codesign；仅适合本地归档/调试检查，不适合蒲公英安装。
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
#   .tokens/pgyer.json     仅 action=upload 时使用。
#   .tokens/dingding.json  上传成功且 notify=on 时使用。
#   .tokens/build.json     可选默认值，例如 api_base。
# Apple 配置：
#   Xcode 必须在当前开发团队下拥有 com.eureka.mindapp 的有效证书和描述文件。

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
    *) echo "警告：忽略未知参数：$arg" ;;
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

[[ "$PUBLISH" =~ ^[0-9]+$ ]] || { echo "错误：publish 必须是数字"; exit 1; }
[[ "$ACTION" =~ ^(build|upload)$ ]] || { echo "错误：iOS action 必须是 build 或 upload"; exit 1; }
[[ "$BUILD_TYPE" =~ ^(release)$ ]] || { echo "错误：iOS type 当前仅支持 release"; exit 1; }
[[ "$EXPORT_METHOD" =~ ^(ad-hoc|development|enterprise|app-store)$ ]] || { echo "错误：export_method 无效"; exit 1; }
[[ "$CODESIGN" =~ ^(on|off)$ ]] || { echo "错误：codesign 必须是 on 或 off"; exit 1; }
[[ "$CLEAN_STEPS" =~ ^(0|3)$ ]] || { echo "错误：clean 必须是 0 或 3"; exit 1; }
[[ "$NOTIFY" =~ ^(on|off)$ ]] || { echo "错误：notify 必须是 on 或 off"; exit 1; }

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
[ -n "$VERSION" ] || { echo "错误：无法从 pubspec.yaml 读取版本号"; exit 1; }
TIMESTAMP="$(date +'%Y-%m-%d-%H-%M-%S')"

echo "=========================================="
echo "Ureka iOS 打包"
echo "  发布模式      : $PUBLISH"
echo "  动作          : $ACTION"
echo "  构建类型      : $BUILD_TYPE"
echo "  导出方式      : $EXPORT_METHOD"
echo "  构建方案      : $SCHEME"
echo "  签名          : $CODESIGN"
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

echo "步骤 2：构建 IPA"
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
[ -n "$SOURCE_IPA" ] && [ -f "$SOURCE_IPA" ] || { echo "错误：build/ios/ipa 下未找到 IPA"; exit 1; }

OUTPUT_DIR="build/ios/ipa_output"
ROOT_OUTPUT_DIR="$PROJECT_ROOT/ipa_output"
mkdir -p "$OUTPUT_DIR" "$ROOT_OUTPUT_DIR"

ARTIFACT_FILE="$OUTPUT_DIR/ureka-ios-${BUILD_TYPE}-${EXPORT_METHOD}-${VERSION}-${TIMESTAMP}.ipa"
cp "$SOURCE_IPA" "$ARTIFACT_FILE"
BACKUP_FILE="$ROOT_OUTPUT_DIR/$(basename "$ARTIFACT_FILE")"
cp "$ARTIFACT_FILE" "$BACKUP_FILE"

echo "步骤 3：产物已准备"
echo "  路径：$ARTIFACT_FILE"
echo "  备份：$BACKUP_FILE"
echo "  大小：$(du -h "$ARTIFACT_FILE" | cut -f1)"

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
  [ -n "$DOWNLOAD_URL" ] || DOWNLOAD_URL="$(json_value "$PGYER_CONFIG" "ios_fallback_url" "")"

  if [ "$NOTIFY" = "on" ]; then
    echo "步骤 5：发送钉钉通知"
    if [ ! -f "$DING_CONFIG" ]; then
      echo "警告：缺少钉钉配置：$DING_CONFIG"
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
      echo "  钉钉通知发送成功"
    else
      echo "警告：钉钉通知发送失败"
    fi
  fi
fi

echo "=========================================="
echo "完成：$ARTIFACT_FILE"
echo "=========================================="
