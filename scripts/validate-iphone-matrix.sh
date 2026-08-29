#!/bin/bash

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /absolute/path/to/SeeNA.app [runtime-id] [output-directory]" >&2
  exit 64
fi

app_path="$1"
runtime_id="${2:-com.apple.CoreSimulator.SimRuntime.iOS-26-5}"
output_directory="${3:-/private/tmp/seena-iphone-matrix}"
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
  local device_name="$1"
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
  "iPhone 14|com.apple.CoreSimulator.SimDeviceType.iPhone-14"
  "iPhone 14 Plus|com.apple.CoreSimulator.SimDeviceType.iPhone-14-Plus"
  "iPhone 14 Pro|com.apple.CoreSimulator.SimDeviceType.iPhone-14-Pro"
  "iPhone 14 Pro Max|com.apple.CoreSimulator.SimDeviceType.iPhone-14-Pro-Max"
  "iPhone 15|com.apple.CoreSimulator.SimDeviceType.iPhone-15"
  "iPhone 15 Plus|com.apple.CoreSimulator.SimDeviceType.iPhone-15-Plus"
  "iPhone 15 Pro|com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro"
  "iPhone 15 Pro Max|com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro-Max"
  "iPhone 16|com.apple.CoreSimulator.SimDeviceType.iPhone-16"
  "iPhone 16 Plus|com.apple.CoreSimulator.SimDeviceType.iPhone-16-Plus"
  "iPhone 16 Pro|com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"
  "iPhone 16 Pro Max|com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max"
  "iPhone 16e|com.apple.CoreSimulator.SimDeviceType.iPhone-16e"
  "iPhone 17|com.apple.CoreSimulator.SimDeviceType.iPhone-17"
  "iPhone Air|com.apple.CoreSimulator.SimDeviceType.iPhone-Air"
  "iPhone 17 Pro|com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
  "iPhone 17 Pro Max|com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"
  "iPhone 17e|com.apple.CoreSimulator.SimDeviceType.iPhone-17e"
)

for entry in "${matrix[@]}"; do
  model_name="${entry%%|*}"
  device_type="${entry##*|}"
  qa_name="SEENA QA ${model_name}"
  screenshot_name="$(printf '%s' "$model_name" | tr '[:upper:] ' '[:lower:]-').png"

  active_device_id="$(device_id_for_name "$qa_name")"
  if [[ -z "$active_device_id" ]]; then
    active_device_id="$(xcrun simctl create "$qa_name" "$device_type" "$runtime_id")"
  fi

  echo "TEST ${model_name} (${active_device_id})"
  xcrun simctl boot "$active_device_id" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$active_device_id" -b >/dev/null
  xcrun simctl install "$active_device_id" "$app_path"
  launch_output="$(xcrun simctl launch --terminate-running-process "$active_device_id" "$bundle_id")"
  launch_pid="${launch_output##*: }"

  if [[ -z "$launch_pid" || "$launch_pid" == "$launch_output" ]]; then
    echo "Launch did not return a process ID for ${model_name}: ${launch_output}" >&2
    exit 70
  fi

  sleep 1
  screenshot_path="${output_directory}/${screenshot_name}"
  xcrun simctl io "$active_device_id" screenshot "$screenshot_path" >/dev/null

  if [[ ! -s "$screenshot_path" ]]; then
    echo "Screenshot was not created for ${model_name}" >&2
    exit 71
  fi

  xcrun simctl terminate "$active_device_id" "$bundle_id"
  xcrun simctl shutdown "$active_device_id"
  active_device_id=""
  echo "PASS ${model_name} pid=${launch_pid} screenshot=${screenshot_path}"
done

trap - EXIT
echo "PASS all ${#matrix[@]} iPhone family simulators"
