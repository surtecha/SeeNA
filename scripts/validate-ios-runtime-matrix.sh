#!/bin/bash

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /absolute/path/to/SeeNA.app [output-directory]" >&2
  exit 64
fi

app_path="$1"
output_directory="${2:-/private/tmp/seena-ios-runtime-matrix}"
device_type="com.apple.CoreSimulator.SimDeviceType.iPhone-14"
bundle_id="com.surtecha.SeeNA"
active_device_id=""

if [[ ! -d "$app_path" ]]; then
  echo "App bundle not found: $app_path" >&2
  exit 66
fi

mkdir -p "$output_directory"

cleanup_active_device() {
  if [[ -n "$active_device_id" ]]; then
    xcrun simctl shutdown "$active_device_id" >/dev/null 2>&1 || true
  fi
}

trap cleanup_active_device EXIT

device_id_for_name() {
  local runtime_id="$1"
  local device_name="$2"
  xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json
import sys

runtime_id = sys.argv[1]
device_name = sys.argv[2]
for device in json.load(sys.stdin).get("devices", {}).get(runtime_id, []):
    if device.get("name") == device_name:
        print(device.get("udid", ""))
        break
' "$runtime_id" "$device_name"
}

matrix=(
  "iOS 16.4|com.apple.CoreSimulator.SimRuntime.iOS-16-4"
  "iOS 17.5|com.apple.CoreSimulator.SimRuntime.iOS-17-5"
  "iOS 18.5|com.apple.CoreSimulator.SimRuntime.iOS-18-5"
  "iOS 26.5|com.apple.CoreSimulator.SimRuntime.iOS-26-5"
)

for entry in "${matrix[@]}"; do
  os_name="${entry%%|*}"
  runtime_id="${entry##*|}"
  qa_name="SEENA QA ${os_name}"
  screenshot_name="$(printf '%s' "$os_name" | tr '[:upper:] ' '[:lower:]-').png"

  if ! xcrun simctl list runtimes available | grep -Fq -- "${os_name} "; then
    echo "Required runtime is not installed: ${os_name}" >&2
    exit 69
  fi

  active_device_id="$(device_id_for_name "$runtime_id" "$qa_name")"
  if [[ -z "$active_device_id" ]]; then
    active_device_id="$(xcrun simctl create "$qa_name" "$device_type" "$runtime_id")"
  fi

  echo "TEST ${os_name} (${active_device_id})"
  xcrun simctl boot "$active_device_id" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$active_device_id" -b >/dev/null
  xcrun simctl install "$active_device_id" "$app_path"
  launch_output="$(xcrun simctl launch --terminate-running-process "$active_device_id" "$bundle_id")"
  launch_pid="${launch_output##*: }"

  if [[ -z "$launch_pid" || "$launch_pid" == "$launch_output" ]]; then
    echo "Launch did not return a process ID for ${os_name}: ${launch_output}" >&2
    exit 70
  fi

  sleep 1
  screenshot_path="${output_directory}/${screenshot_name}"
  xcrun simctl io "$active_device_id" screenshot "$screenshot_path" >/dev/null

  if [[ ! -s "$screenshot_path" ]]; then
    echo "Screenshot was not created for ${os_name}" >&2
    exit 71
  fi

  xcrun simctl terminate "$active_device_id" "$bundle_id"
  xcrun simctl shutdown "$active_device_id"
  active_device_id=""
  echo "PASS ${os_name} pid=${launch_pid} screenshot=${screenshot_path}"
done

trap - EXIT
echo "PASS all ${#matrix[@]} supported iOS major-version runtimes"
