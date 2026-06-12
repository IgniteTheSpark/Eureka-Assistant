#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

repo_name="BRSpecs"
repo_url="git@git.100credit.cn:ai2c/app/cocoapods-specs.git"
target_pods=("BRBluetoothLib" "BROpusConvertLib")

current_step="初始化"
failure_reason=""
report_printed="false"
specs_repo_result="未检查"
podfile_dir="$(pwd)"
install_result="未执行"
skip_reason=""
refreshed_pods=()
cleaned_cache=()
cleaned_dirs=()
step_names=()
step_states=()
step_notes=()

start_step() {
  current_step="$1"
  step_names+=("$current_step")
  step_states+=("RUNNING")
  step_notes+=("")
}

finish_step() {
  local note="${1:-}"
  local index
  index=$((${#step_names[@]} - 1))
  if (( index >= 0 )); then
    step_states[$index]="OK"
    step_notes[$index]="$note"
  fi
}

mark_current_step_failed() {
  local note="$1"
  local index
  index=$((${#step_names[@]} - 1))
  if (( index >= 0 )) && [[ "${step_states[$index]}" == "RUNNING" ]]; then
    step_states[$index]="FAIL"
    step_notes[$index]="$note"
  fi
}

abort_refresh() {
  failure_reason="$1"
  mark_current_step_failed "$failure_reason"
  exit 1
}

join_by_space() {
  if (( $# == 0 )); then
    echo "无"
  else
    printf '%s' "$1"
    shift
    printf ' %s' "$@"
    echo
  fi
}

array_length() {
  local array_name="$1"
  eval "echo \${#${array_name}[@]}"
}

join_array_by_name() {
  local array_name="$1"
  local count i value
  count="$(array_length "$array_name")"

  if (( count == 0 )); then
    echo "无"
    return
  fi

  for (( i = 0; i < count; i++ )); do
    eval "value=\"\${${array_name}[${i}]}\""
    if (( i == 0 )); then
      printf '%s' "$value"
    else
      printf ' %s' "$value"
    fi
  done
  echo
}

lock_version_for() {
  local pod_name="$1"
  if [[ ! -f Podfile.lock ]]; then
    echo "Podfile.lock 不存在"
    return
  fi

  sed -n "s/^  - ${pod_name} (\([^)]*\)).*/\1/p" Podfile.lock | head -n 1
}

print_report() {
  local exit_code="$1"
  local status="失败"
  local i pod version note

  if [[ "$report_printed" == "true" ]]; then
    return
  fi
  report_printed="true"

  if [[ "$exit_code" -eq 0 ]]; then
    status="成功"
  elif [[ -z "$failure_reason" ]]; then
    failure_reason="命令返回非 0，详见上方原始输出。"
    mark_current_step_failed "$failure_reason"
  fi

  echo
  echo "========== Pods 刷新结果 =========="
  echo "Podfile 目录: ${podfile_dir}"
  echo "刷新状态: ${status}"
  echo "目标 Pods: $(join_array_by_name refreshed_pods)"
  echo "Specs repo: ${specs_repo_result}"
  echo "预解析安装: ${install_result}"
  echo "清理缓存: $(join_array_by_name cleaned_cache)"
  echo "清理目录: $(join_array_by_name cleaned_dirs)"
  if [[ -n "$skip_reason" ]]; then
    echo "跳过刷新: ${skip_reason}"
  fi

  if [[ "$exit_code" -ne 0 ]]; then
    echo "失败阶段: ${current_step}"
    echo "失败原因: ${failure_reason}"
  fi

  if [[ -f Podfile.lock ]] && (( $(array_length refreshed_pods) > 0 )); then
    echo "Podfile.lock 版本:"
    for pod in "${refreshed_pods[@]}"; do
      version="$(lock_version_for "$pod")"
      if [[ -n "$version" ]]; then
        echo "  ${pod}: ${version}"
      else
        echo "  ${pod}: 未在 Podfile.lock 中找到"
      fi
    done
  fi

  echo "步骤:"
  for (( i = 0; i < ${#step_names[@]}; i++ )); do
    note="${step_notes[$i]}"
    if [[ -n "$note" ]]; then
      echo "  [${step_states[$i]}] ${step_names[$i]} - ${note}"
    else
      echo "  [${step_states[$i]}] ${step_names[$i]}"
    fi
  done
  echo "==================================="
}

on_exit() {
  local exit_code="$1"
  print_report "$exit_code"
}

trap 'on_exit $?' EXIT

contains_pod_dependency() {
  local pod_name="$1"

  if grep -Eq "^[[:space:]]*pod[[:space:]]+['\"]${pod_name}['\"]" Podfile; then
    return 0
  fi

  if [[ -f Podfile.lock ]] && grep -Eq "^  - ${pod_name}( |\\(|:)" Podfile.lock; then
    return 0
  fi

  return 1
}

detect_target_pods() {
  local pod
  refreshed_pods=()

  for pod in "${target_pods[@]}"; do
    if contains_pod_dependency "$pod"; then
      refreshed_pods+=("$pod")
    fi
  done

  (( $(array_length refreshed_pods) > 0 ))
}

ensure_podfile_dir() {
  if [[ ! -f Podfile ]]; then
    echo "Error: 当前目录没有 Podfile。"
    echo "请把脚本放到 Podfile 同级目录执行。"
    abort_refresh "当前目录没有 Podfile。"
  fi
}

ensure_specs_repo() {
  local repo_dir="${HOME}/.cocoapods/repos/${repo_name}"

  if pod repo list 2>/dev/null | grep -Eq "^[[:space:]]*${repo_name}[[:space:]]*$|^[[:space:]]*- Name:[[:space:]]*${repo_name}[[:space:]]*$"; then
    specs_repo_result="已存在 ${repo_name}"
  elif [[ -d "$repo_dir" ]] && [[ -n "$(ls -A "$repo_dir" 2>/dev/null)" ]]; then
    specs_repo_result="已存在本地目录 ${repo_dir}"
  else
    pod repo add "$repo_name" "$repo_url"
    specs_repo_result="已添加 ${repo_name}"
  fi
}

update_specs_repo() {
  pod repo update "$repo_name"
  specs_repo_result="${specs_repo_result}; 已更新 ${repo_name}"
}

clean_pod_cache() {
  local pod
  for pod in "${refreshed_pods[@]}"; do
    pod cache clean "$pod" --all
    cleaned_cache+=("$pod")
  done
}

clean_installed_pods() {
  local pod dir
  for pod in "${refreshed_pods[@]}"; do
    dir="Pods/${pod}"
    if [[ -d "$dir" ]]; then
      rm -rf "$dir"
      cleaned_dirs+=("$dir")
    fi
  done
}

refresh_pods() {
  pod update "${refreshed_pods[@]}" --repo-update
}

install_for_dependency_resolution() {
  pod install --repo-update
  install_result="已执行 pod install --repo-update"
}

start_step "校验 Podfile 目录"
ensure_podfile_dir
finish_step

start_step "检查 CocoaPods Specs repo"
ensure_specs_repo
finish_step "$specs_repo_result"

start_step "更新 CocoaPods Specs repo"
update_specs_repo
finish_step "$specs_repo_result"

start_step "初始识别 SDK 依赖"
if detect_target_pods; then
  finish_step "$(join_array_by_name refreshed_pods)"
else
  finish_step "未发现，准备先执行 pod install 解析间接依赖"

  start_step "解析间接依赖"
  install_for_dependency_resolution
  finish_step "$install_result"

  start_step "二次识别 SDK 依赖"
  if detect_target_pods; then
    finish_step "$(join_array_by_name refreshed_pods)"
  else
    skip_reason="pod install 后仍未解析出 BRBluetoothLib / BROpusConvertLib，当前项目无需刷新。"
    finish_step "$skip_reason"
    echo "$skip_reason"
    exit 0
  fi
fi

start_step "清理 CocoaPods 缓存"
clean_pod_cache
finish_step "$(join_array_by_name cleaned_cache)"

start_step "清理已安装 Pods 目录"
clean_installed_pods
finish_step "$(join_array_by_name cleaned_dirs)"

start_step "按当前配置刷新 Pods"
refresh_pods
finish_step

echo "完成目标 Pods 刷新。"
