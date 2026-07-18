#!/bin/bash

# The production scheme builds this target as a companion during local Debug
# runs. Keep the Dev binary side-by-side with the primary app, but never make
# an archive, test, or destination-less build fail because there is nowhere to
# install it. The marker is set only by a Dev target that participated in this
# build action, so the scheme's shared post-action is inert for tests and CI.
set -euo pipefail

if [[ "${CONFIGURATION:-}" != "Debug" ]]; then
  exit 0
fi

marker_path="${PROJECT_TEMP_DIR:?Missing PROJECT_TEMP_DIR}/earnline-dev-ready-to-install"
if [[ ! -f "$marker_path" ]]; then
  echo "note: earnline Dev was not built for this action; installation skipped." >&2
  exit 0
fi

destination_id="${TARGET_DEVICE_IDENTIFIER:-}"
if [[ -z "$destination_id" || "$destination_id" == *"DVTiPhonePlaceholder"* ]]; then
  echo "note: earnline Dev was built but not installed because Xcode has no concrete run destination." >&2
  exit 0
fi

app_path="${TARGET_BUILD_DIR:?Missing TARGET_BUILD_DIR}/${WRAPPER_NAME:?Missing WRAPPER_NAME}"
if [[ ! -d "$app_path" ]]; then
  echo "error: earnline Dev was built without an installable app at $app_path." >&2
  exit 1
fi

case "${PLATFORM_NAME:-}" in
  iphonesimulator)
    xcrun simctl install "$destination_id" "$app_path"
    ;;
  iphoneos)
    xcrun devicectl device install app --device "$destination_id" "$app_path"
    ;;
  *)
    echo "note: earnline Dev was built for ${PLATFORM_NAME:-an unknown platform}; installation skipped." >&2
    ;;
esac
