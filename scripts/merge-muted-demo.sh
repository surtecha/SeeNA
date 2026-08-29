#!/bin/zsh

set -euo pipefail

if [[ "$#" -lt 3 || "$#" -gt 4 ]]; then
  print -u2 "Usage: $0 <60-second-journey.mp4> <results.mp4> <output.mp4> [--overwrite]"
  exit 64
fi

script_dir="${0:A:h}"
build_dir="$(mktemp -d /private/tmp/seena-muted-demo.XXXXXX)"
trap 'rm -rf "$build_dir"' EXIT

xcrun swiftc \
  -parse-as-library \
  -framework AVFoundation \
  -framework CryptoKit \
  "$script_dir/MergeMutedDemo.swift" \
  -o "$build_dir/MergeMutedDemo"

"$build_dir/MergeMutedDemo" "$@"
