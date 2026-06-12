#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ] || [ "${BASH##*/}" = "sh" ]; then
  echo "Error: 请使用 bash 执行本脚本，例如：bash $0"
  exit 2
fi

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
flutter_package="br_flutter_plugin_ble"
android_dir="${project_root}/android"
android_refresh_script="refresh-bairong.sh"
ios_dir="${project_root}/ios"
ios_refresh_script="refresh_remote_pods.sh"

current_step="初始化"
failure_reason=""
report_printed="false"
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

print_report() {
  local exit_code="$1"
  local status="失败"
  local i note

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
  echo "========== 插件依赖刷新结果 =========="
  echo "项目根目录: ${project_root}"
  echo "Flutter 插件: ${flutter_package}"
  echo "状态: ${status}"
  if [[ "$exit_code" -ne 0 ]]; then
    echo "失败阶段: ${current_step}"
    echo "失败原因: ${failure_reason}"
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
  echo "======================================"
}

on_exit() {
  local exit_code="$1"
  cd "$project_root"
  print_report "$exit_code"
}

trap 'on_exit $?' EXIT

ensure_project_root() {
  if [[ ! -f "${project_root}/pubspec.yaml" ]]; then
    echo "Error: 项目根目录缺少 pubspec.yaml: ${project_root}"
    echo "请把脚本放到 Flutter 项目根目录执行。"
    abort_refresh "项目根目录缺少 pubspec.yaml。"
  fi
}

ensure_android_refresh_script() {
  if [[ ! -d "$android_dir" ]]; then
    echo "Error: Android 目录不存在: ${android_dir}"
    abort_refresh "Android 目录不存在。"
  fi

  if [[ ! -f "${android_dir}/${android_refresh_script}" ]]; then
    echo "Error: Android 刷新脚本不存在: ${android_dir}/${android_refresh_script}"
    abort_refresh "Android 刷新脚本不存在。"
  fi
}

ensure_ios_refresh_script() {
  if [[ ! -d "$ios_dir" ]]; then
    echo "Error: iOS 目录不存在: ${ios_dir}"
    abort_refresh "iOS 目录不存在。"
  fi

  if [[ ! -f "${ios_dir}/${ios_refresh_script}" ]]; then
    echo "Error: iOS 刷新脚本不存在: ${ios_dir}/${ios_refresh_script}"
    abort_refresh "iOS 刷新脚本不存在。"
  fi
}

refresh_flutter_plugin() {
  cd "$project_root"
  flutter pub upgrade "$flutter_package"
}

refresh_android_dependencies() {
  cd "$android_dir"
  sh "$android_refresh_script"
}

refresh_ios_dependencies() {
  cd "$ios_dir"
  bash "$ios_refresh_script"
}

start_step "检查项目根目录"
ensure_project_root
finish_step

start_step "检查 Android 刷新脚本"
ensure_android_refresh_script
finish_step

start_step "检查 iOS 刷新脚本"
ensure_ios_refresh_script
finish_step

start_step "刷新 Flutter 插件依赖"
refresh_flutter_plugin
finish_step "flutter pub upgrade ${flutter_package}"

start_step "刷新 Android 依赖"
refresh_android_dependencies
finish_step "sh ${android_refresh_script}"

start_step "刷新 iOS 依赖"
refresh_ios_dependencies
finish_step "bash ${ios_refresh_script}"

start_step "回到项目根目录"
cd "$project_root"
finish_step

echo "完成 ${flutter_package} 插件和原生依赖刷新。"
