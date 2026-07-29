#!/bin/zsh

# Capture a semantic iOS Simulator snapshot without desktop automation.
# Output is ignored because an Earnline screen can contain private ledger data.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ios-app/Scripts/inspect-simulator-screen.sh [--udid <UDID>] [--bundle-id <bundle-id>]

Starts a temporary local Appium XCUITest session, saves a PNG screenshot and
the accessibility XML tree under .ios-simulator-output/, then closes both.
When more than one simulator is booted, pass --udid explicitly.
EOF
}

simulator_udid=""
bundle_id="com.earnline.app"

while (( $# > 0 )); do
  case "$1" in
    --udid)
      simulator_udid="${2:-}"
      shift 2
      ;;
    --bundle-id)
      bundle_id="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      print -u2 "error: Unknown option: $1"
      usage >&2
      exit 64
      ;;
  esac
done

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
xcode_developer_dir="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
appium_root="${EARNLINE_APPIUM_ROOT:-$HOME/.local/share/codex-tools/appium}"
appium_bin="$appium_root/node_modules/.bin/appium"
appium_home="$appium_root/home"
appium_port="${EARNLINE_APPIUM_PORT:-4723}"
output_dir="$repo_root/.ios-simulator-output"

if [[ ! -d "$xcode_developer_dir" ]]; then
  print -u2 "error: Xcode developer directory not found: $xcode_developer_dir"
  exit 69
fi

if [[ ! -x "$appium_bin" ]]; then
  print -u2 "error: Appium is not installed at $appium_bin"
  print -u2 "Install the local XCUITest toolchain before retrying."
  exit 69
fi

for required_command in curl jq base64; do
  if ! command -v "$required_command" >/dev/null; then
    print -u2 "error: Missing required command: $required_command"
    exit 69
  fi
done

xcode_version="$(DEVELOPER_DIR="$xcode_developer_dir" xcodebuild -version | sed -n '1p')"
if [[ "$xcode_version" != Xcode\ 27.* ]]; then
  print -u2 "error: Expected Xcode 27, found: $xcode_version"
  exit 69
fi

booted_devices_json="$(DEVELOPER_DIR="$xcode_developer_dir" xcrun simctl list -j devices booted)"
if [[ -z "$simulator_udid" ]]; then
  booted_udids=("${(@f)$(print -r -- "$booted_devices_json" | jq -r '.devices[][] | select(.state == "Booted") | .udid')}")
  if (( ${#booted_udids[@]} != 1 )); then
    print -u2 "error: Expected exactly one booted simulator; found ${#booted_udids[@]}. Pass --udid explicitly."
    exit 69
  fi
  simulator_udid="$booted_udids[1]"
fi

device_name="$(print -r -- "$booted_devices_json" | jq -r --arg udid "$simulator_udid" '.devices[][] | select(.udid == $udid) | .name' | sed -n '1p')"
if [[ -z "$device_name" || "$device_name" == "null" ]]; then
  print -u2 "error: $simulator_udid is not a booted simulator."
  exit 69
fi

DEVELOPER_DIR="$xcode_developer_dir" xcrun simctl bootstatus "$simulator_udid" -b >/dev/null
mkdir -p "$output_dir"

capture_stamp="$(date -u +%Y%m%dT%H%M%SZ)"
appium_log="$output_dir/appium-$capture_stamp.log"
source_path="$output_dir/appium-$capture_stamp.xml"
screenshot_path="$output_dir/appium-$capture_stamp.png"
appium_session_id=""
appium_pid=""

cleanup() {
  if [[ -n "$appium_session_id" ]]; then
    curl --silent --output /dev/null --max-time 15 --request DELETE "http://127.0.0.1:$appium_port/session/$appium_session_id" || true
  fi
  if [[ -n "$appium_pid" ]]; then
    kill "$appium_pid" 2>/dev/null || true
    wait "$appium_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

DEVELOPER_DIR="$xcode_developer_dir" APPIUM_HOME="$appium_home" "$appium_bin" server --address 127.0.0.1 --port "$appium_port" --log "$appium_log" >>"$appium_log" 2>&1 &
appium_pid="$!"

for _ in {1..60}; do
  if curl --silent --fail --max-time 1 "http://127.0.0.1:$appium_port/status" >/dev/null; then
    break
  fi
  sleep 0.5
done

if ! curl --silent --fail --max-time 1 "http://127.0.0.1:$appium_port/status" >/dev/null; then
  print -u2 "error: Appium did not start. See $appium_log"
  exit 69
fi

session_payload="$(jq -n \
  --arg udid "$simulator_udid" \
  --arg device_name "$device_name" \
  --arg bundle_id "$bundle_id" \
  '{capabilities: {alwaysMatch: {platformName: "iOS", "appium:automationName": "XCUITest", "appium:udid": $udid, "appium:deviceName": $device_name, "appium:bundleId": $bundle_id, "appium:noReset": true, "appium:shouldTerminateApp": false, "appium:connectHardwareKeyboard": true, "appium:newCommandTimeout": 120}, firstMatch: [{}]}}')"

session_response="$(curl --fail-with-body --silent --show-error --max-time 180 \
  --header 'Content-Type: application/json' \
  --data "$session_payload" \
  "http://127.0.0.1:$appium_port/session")"
appium_session_id="$(print -r -- "$session_response" | jq -r '.value.sessionId // .sessionId // empty')"

if [[ -z "$appium_session_id" ]]; then
  print -u2 "error: Appium did not return a session ID. See $appium_log"
  exit 70
fi

curl --fail-with-body --silent --show-error --max-time 45 \
  "http://127.0.0.1:$appium_port/session/$appium_session_id/source" \
  | jq -r '.value' > "$source_path"
curl --fail-with-body --silent --show-error --max-time 45 \
  "http://127.0.0.1:$appium_port/session/$appium_session_id/screenshot" \
  | jq -r '.value' | base64 -D > "$screenshot_path"

element_count="$(rg -o '<XCUIElementType' "$source_path" | wc -l | tr -d ' ')"
if (( element_count <= 1 )); then
  print -u2 "error: Appium returned an empty accessibility hierarchy. See $source_path and $appium_log"
  exit 70
fi

print "Simulator: $device_name ($simulator_udid)"
print "Accessibility elements: $element_count"
print "Hierarchy: $source_path"
print "Screenshot: $screenshot_path"
