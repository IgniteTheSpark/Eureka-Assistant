#!/bin/bash
#
# Upload an APK/IPA package to PGYER fast upload API.

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
  echo "error: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ./pgyer_upload.sh -k <api_key> [options] <file>

Options:
  -k <api_key>       PGYER API key. Required.
  -t <type>          Install type: 1=public, 2=password, 3=invite.
  -p <password>      Install password, required when type=2.
  -d <desc>          Update description.
  -c <shortcut>      Channel shortcut.
  -P                 Show curl progress bar.
  -j                 Print final JSON response.
  -v                 Verbose logs.
  -h                 Show help.
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
        log "Using PGYER API domain: $domain"
      fi
      return
    fi
  done
  fail "all PGYER API domains are unreachable"
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

[ -n "$api_key" ] || fail "PGYER API key is required"
[ -n "$file" ] || fail "package file is required"
[ -f "$file" ] || fail "file not found: $file"

build_type="${file##*.}"
if [[ ! " ${SUPPORTED_TYPES[*]} " =~ " ${build_type} " ]]; then
  fail "unsupported file type: $build_type"
fi

select_domain

log "Step 1/3: getting PGYER upload token"
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

[ -n "$endpoint" ] || fail "failed to parse PGYER upload endpoint: $token_response"
[ -n "$cos_key" ] || fail "failed to parse PGYER build key: $token_response"
[ -n "$signature" ] || fail "failed to parse PGYER upload signature: $token_response"
[ -n "$security_token" ] || fail "failed to parse PGYER security token: $token_response"

log "Step 2/3: uploading $(basename "$file")"
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

[ "$http_code" = "204" ] || fail "upload failed with HTTP status $http_code"

log "Step 3/3: waiting for PGYER build processing"
final_response=""
for i in $(seq 1 60); do
  final_response=$(curl -s "${API_BASE_URL}/app/buildInfo?_api_key=${api_key}&buildKey=${cos_key}")
  code=$(json_find "$final_response" "code")
  if [ "$code" = "0" ]; then
    break
  fi
  printf "\rprocessing... %ss" "$i" >&2
  sleep 1
done
printf "\r\033[K" >&2

code=$(json_find "$final_response" "code")
[ "$code" = "0" ] || fail "PGYER build check failed: $final_response"

shortcut=$(json_find "$final_response" "buildShortcutUrl")
build_key=$(json_find "$final_response" "buildKey")
version=$(json_find "$final_response" "buildVersion")
version_no=$(json_find "$final_response" "buildVersionNo")
app_name=$(json_find "$final_response" "buildName")

log "PGYER upload completed"
[ -n "$app_name" ] && echo "App: $app_name"
[ -n "$version" ] && echo "Version: $version ($version_no)"
if [ -n "$shortcut" ]; then
  echo "URL: https://${WEB_DOMAIN}/${shortcut}"
elif [ -n "$build_key" ]; then
  echo "URL: https://${WEB_DOMAIN}/${build_key}"
fi

if [ "$JSON_OUTPUT" -eq 1 ]; then
  echo "Full JSON Response:"
  echo "$final_response"
fi
