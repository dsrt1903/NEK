#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

device="${1:-}"
if [[ -z "$device" ]]; then
  device="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
groups = sorted(json.load(sys.stdin)["devices"].items(), reverse=True)
print(next(d["udid"] for _, users in groups for d in users if d["name"].startswith("iPhone")))' )"
fi
mkdir -p .build
output="$(mktemp -d)"
server_pid=""
video_pid=""
cleanup() {
  if [[ -n "$video_pid" ]]; then kill -INT "$video_pid" 2>/dev/null || true; wait "$video_pid" || true; fi
  if [[ -n "$server_pid" ]]; then kill "$server_pid" 2>/dev/null || true; wait "$server_pid" || true; fi
  rm -rf "$output"
}
trap cleanup EXIT

DB_PATH="$output/demo.sqlite" node src/server/main.js > "$output/api.log" 2>&1 &
server_pid=$!
for attempt in {1..30}; do
  kill -0 "$server_pid"
  if curl -fsS http://127.0.0.1:8080/api/health > /dev/null 2>&1; then break; fi
  sleep 1
done
curl -fsS http://127.0.0.1:8080/api/health > /dev/null

xcrun simctl bootstatus "$device" -b
xcrun simctl status_bar "$device" override --time '09:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState unplugged --batteryLevel 100
xcodebuild -project NEK.xcodeproj -scheme NEK -destination "id=$device" \
  -derivedDataPath .build -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO build-for-testing

xcrun simctl io "$device" recordVideo --codec=h264 "$output/recording.mp4" &
video_pid=$!
xcodebuild -project NEK.xcodeproj -scheme NEK -destination "id=$device" \
  -derivedDataPath .build -parallel-testing-enabled NO -resultBundlePath "$output/demo.xcresult" \
  CODE_SIGNING_ALLOWED=NO test-without-building
kill -INT "$video_pid" 2>/dev/null || true
wait "$video_pid" || true
video_pid=""
xcrun simctl status_bar "$device" clear

xcrun xcresulttool export attachments --path "$output/demo.xcresult" --output-path "$output/attachments"
python3 - "$output/attachments" <<'PY'
import json, pathlib, shutil, sys

source = pathlib.Path(sys.argv[1])
screens = ("01-login", "02-booking", "03-client-visits", "04-studio-calendar")
attachments = [item for test in json.loads((source / "manifest.json").read_text()) for item in test["attachments"]]
for name in screens:
    match = next(item for item in attachments if name in item["suggestedHumanReadableName"])
    shutil.copyfile(source / match["exportedFileName"], pathlib.Path("docs/screenshots") / (name + ".png"))
PY
swiftc -parse-as-library -module-cache-path .build \
  tests/trim-video.swift -o "$output/trim-video"
"$output/trim-video" "$output/recording.mp4" docs/demo.mp4
