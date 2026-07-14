#!/bin/sh
set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: $0 <gpx-directory> [output.json]" >&2
  exit 64
fi

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
native_root="$repo_root/ios-native"
build_root="${TMPDIR:-/tmp}/memory-lanes-rider-craft-calibration"
binary="$build_root/rider-craft-calibration"

mkdir -p "$build_root"
export CLANG_MODULE_CACHE_PATH="$build_root/module-cache"
export SWIFT_MODULE_CACHE_PATH="$build_root/module-cache"

xcrun swiftc -parse-as-library -O -o "$binary" \
  "$native_root/MemoryLanes/Models/Coordinate.swift" \
  "$native_root/MemoryLanes/Models/RecordingPoint.swift" \
  "$native_root/MemoryLanes/Models/GPXTrack.swift" \
  "$native_root/MemoryLanes/Models/Ride.swift" \
  "$native_root/MemoryLanes/Models/RideDetail.swift" \
  "$native_root/MemoryLanes/Models/PlannedRoute.swift" \
  "$native_root/MemoryLanes/Models/RideRecommendation.swift" \
  "$native_root/MemoryLanes/Models/RiderCraft.swift" \
  "$native_root/MemoryLanes/Services/GPXParser.swift" \
  "$native_root/MemoryLanes/Services/RiderCraftAnalyzer.swift" \
  "$native_root/MemoryLanes/Services/RideCoachAnalyzer.swift" \
  "$native_root/Tools/RiderCraftCalibration/main.swift"

"$binary" "$@"
