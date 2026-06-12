#!/bin/bash
#
# 上传 APK/IPA 到蒲公英快速上传接口。

set -euo pipefail

readonly API_DOMAINS=("api.pgyer.com" "api.xcxwo.com" "api.pgyeraapp.com")
readonly SUPPORTED_TYPES=("ipa" "apk" "hap")

API_BASE_URL=""
WEB_DOMAIN=""
PROGRESS_ENABLE=0
JSON_OUTPUT=0
VERBOSE_MODE=0

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

fail() {
  echo "错误：$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
用法：./pgyer_upload.sh -k <api_key> [选项] <文件>

选项：
  -k <api_key>       蒲公英 API Key，必填。
  -t <type>          安装方式：1=公开，2=密码，3=邀请。
  -p <password>      安装密码；type=2 时需要。
  -d <desc>          更新说明。
  -c <shortcut>      渠道短链接。
  -P                 显示 curl 上传进度。
  -j                 打印最终 JSON 响应。
  -v                 输出详细日志。
  -h                 显示帮助。
EOF
}

json_find() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

raw = sys.argv[1]
name = sys.argv[2]

def walk(value):
    if isinstance(value, dict):
        if name in value and value[name] is not None:
            return value[name]
        for item in value.values():
            found = walk(item)
            if found is not None:
                return found
    elif isinstance(value, list):
        for item in value:
            found = walk(item)
            if found is not None:
                return found
    return None

try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

found = walk(data)
if found is not None:
    print(found)
PY
}

select_domain() {
  for domain in "${API_DOMAINS[@]}"; do
    local test_url="https://${domain}/apiv2/app/getCOSToken"
    local http_code
    http_code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 "$test_url" || true)
    if [ "$http_code" != "000" ] && [ -n "$http_code" ]; then
      API_BASE_URL="https://${domain}/apiv2"
      WEB_DOMAIN="${domain#api.}"
      if [ "$VERBOSE_MODE" -eq 1 ]; then
        log "使用蒲公英接口域名：$domain"
      fi
      return
    fi
  done
  fail "所有蒲公英接口域名均不可达"
}

api_key=""
install_type=""
install_password=""
update_description=""
channel_shortcut=""

while getopts 'k:t:p:d:c:Pjvh' opt; do
  case "$opt" in
    k) api_key="$OPTARG" ;;
    t) install_type="$OPTARG" ;;
    p) install_password="$OPTARG" ;;
    d) update_description="$OPTARG" ;;
    c) channel_shortcut="$OPTARG" ;;
    P) PROGRESS_ENABLE=1 ;;
    j) JSON_OUTPUT=1 ;;
    v) VERBOSE_MODE=1 ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

shift $((OPTIND - 1))
file="${1:-}"

[ -n "$api_key" ] || fail "缺少蒲公英 API Key"
[ -n "$file" ] || fail "缺少待上传文件"
[ -f "$file" ] || fail "文件不存在：$file"

build_type="${file##*.}"
if [[ ! " ${SUPPORTED_TYPES[*]} " =~ " ${build_type} " ]]; then
  fail "不支持的文件类型：$build_type"
fi

select_domain

log "步骤 1/3：获取蒲公英上传凭证"
token_args=(
  --form-string "_api_key=${api_key}"
  --form-string "buildType=${build_type}"
)
[ -n "$install_type" ] && token_args+=(--form-string "buildInstallType=${install_type}")
[ -n "$install_password" ] && token_args+=(--form-string "buildPassword=${install_password}")
[ -n "$update_description" ] && token_args+=(--form-string "buildUpdateDescription=${update_description}")
[ -n "$channel_shortcut" ] && token_args+=(--form-string "buildChannelShortcut=${channel_shortcut}")
token_response=$(
  curl -s \
    "${token_args[@]}" \
    "${API_BASE_URL}/app/getCOSToken"
)

endpoint=$(json_find "$token_response" "endpoint")
cos_key=$(json_find "$token_response" "key")
signature=$(json_find "$token_response" "signature")
security_token=$(json_find "$token_response" "x-cos-security-token")

[ -n "$endpoint" ] || fail "无法解析蒲公英上传地址：$token_response"
[ -n "$cos_key" ] || fail "无法解析蒲公英构建 Key：$token_response"
[ -n "$signature" ] || fail "无法解析蒲公英上传签名：$token_response"
[ -n "$security_token" ] || fail "无法解析蒲公英安全令牌：$token_response"

log "步骤 2/3：上传 $(basename "$file")"
progress_option="-s"
[ "$PROGRESS_ENABLE" -eq 1 ] && progress_option="--progress-bar"

http_code=$(
  curl -o /dev/null -w '%{http_code}' \
    $progress_option \
    --connect-timeout 30 \
    --max-time 1800 \
    --form-string "key=${cos_key}" \
    --form-string "signature=${signature}" \
    --form-string "x-cos-security-token=${security_token}" \
    --form-string "x-cos-meta-file-name=$(basename "$file")" \
    -F "file=@${file}" \
    "$endpoint"
)

[ "$http_code" = "204" ] || fail "上传失败，HTTP 状态码：$http_code"

log "步骤 3/3：等待蒲公英处理构建信息"
final_response=""
for i in $(seq 1 60); do
  final_response=$(curl -s "${API_BASE_URL}/app/buildInfo?_api_key=${api_key}&buildKey=${cos_key}")
  code=$(json_find "$final_response" "code")
  if [ "$code" = "0" ]; then
    break
  fi
  printf "\r处理中... %ss" "$i" >&2
  sleep 1
done
printf "\r\033[K" >&2

code=$(json_find "$final_response" "code")
[ "$code" = "0" ] || fail "蒲公英构建检查失败：$final_response"

shortcut=$(json_find "$final_response" "buildShortcutUrl")
build_key=$(json_find "$final_response" "buildKey")
version=$(json_find "$final_response" "buildVersion")
version_no=$(json_find "$final_response" "buildVersionNo")
app_name=$(json_find "$final_response" "buildName")

log "蒲公英上传完成"
[ -n "$app_name" ] && echo "应用：$app_name"
[ -n "$version" ] && echo "版本：$version ($version_no)"
if [ -n "$shortcut" ]; then
  echo "下载地址：https://${WEB_DOMAIN}/${shortcut}"
  echo "URL: https://${WEB_DOMAIN}/${shortcut}"
elif [ -n "$build_key" ]; then
  echo "下载地址：https://${WEB_DOMAIN}/${build_key}"
  echo "URL: https://${WEB_DOMAIN}/${build_key}"
fi

if [ "$JSON_OUTPUT" -eq 1 ]; then
  echo "完整 JSON 响应："
  echo "$final_response"
fi
