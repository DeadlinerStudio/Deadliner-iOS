#!/usr/bin/env bash

set -euo pipefail

IOS_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_CORE_REPO="/Users/aritxonly/Codes/Agent/deadliner_core"
CORE_REPO="${1:-$DEFAULT_CORE_REPO}"

SRC_XCFRAMEWORK="$CORE_REPO/dist/ios/ffi_uniffi.xcframework"
SRC_SWIFT_BINDING="$CORE_REPO/dist/ios/bindings/ffi_uniffi.swift"

DEST_XCFRAMEWORK="$IOS_REPO_ROOT/Vendor/DeadlinerCore/ffi_uniffi.xcframework"
DEST_SWIFT_BINDING="$IOS_REPO_ROOT/DeadlinerCoreSupport/Generated/ffi_uniffi.swift"

require_path() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    echo "error: missing required path: $path" >&2
    exit 1
  fi
}

patch_uniffi_swift() {
  local swift_file="$1"

  SWIFT_FILE="$swift_file" python3 - <<'PY'
from pathlib import Path
import os

path = Path(os.environ["SWIFT_FILE"])
text = path.read_text()

wrapper = """fileprivate let uniffiFutureContinuationCallbackFn: UniffiRustFutureContinuationCallback = { handle, pollResult in
    uniffiFutureContinuationCallback(handle: handle, pollResult: pollResult)
}

"""

needle = "fileprivate func uniffiFutureContinuationCallback(handle: UInt64, pollResult: Int8) {"

if "uniffiFutureContinuationCallbackFn" not in text:
    if needle not in text:
        raise SystemExit(f"error: failed to find callback insertion point in {path}")
    text = text.replace(needle, wrapper + needle, 1)

old = "                uniffiFutureContinuationCallback,\n"
new = "                uniffiFutureContinuationCallbackFn,\n"
if old not in text and new not in text:
    raise SystemExit(f"error: failed to find callback call site in {path}")
text = text.replace(old, new)

path.write_text(text)
PY
}

echo "==> Syncing Deadliner core iOS artifacts"
echo "    core repo: $CORE_REPO"

require_path "$SRC_XCFRAMEWORK"
require_path "$SRC_SWIFT_BINDING"

mkdir -p "$(dirname "$DEST_XCFRAMEWORK")"
mkdir -p "$(dirname "$DEST_SWIFT_BINDING")"

rm -rf "$DEST_XCFRAMEWORK"
cp -R "$SRC_XCFRAMEWORK" "$DEST_XCFRAMEWORK"
cp "$SRC_SWIFT_BINDING" "$DEST_SWIFT_BINDING"

echo "==> Applying Swift callback compatibility patch"
patch_uniffi_swift "$DEST_SWIFT_BINDING"

echo "==> Synced:"
echo "    xcframework -> $DEST_XCFRAMEWORK"
echo "    swift binding -> $DEST_SWIFT_BINDING"
