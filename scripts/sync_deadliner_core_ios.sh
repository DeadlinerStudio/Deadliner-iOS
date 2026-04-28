#!/usr/bin/env bash

set -euo pipefail

IOS_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_CORE_REPO="/Users/aritxonly/Codes/Agent/deadliner_core"
DEFAULT_RELEASE_REPO="DeadlinerStudio/LifiAI-Core"
DEFAULT_RELEASE_TAG="nightly"
ARTIFACT_NAME="deadliner-ios.zip"
CACHE_ROOT="${IOS_REPO_ROOT}/.deadliner-core/cache"
STATE_FILE="${IOS_REPO_ROOT}/.deadliner-core/ios-sync-state.json"

MODE="${1:-${DEADLINER_CORE_SOURCE:-release}}"
RELEASE_TAG="${DEADLINER_CORE_TAG:-$DEFAULT_RELEASE_TAG}"
RELEASE_REPO="${DEADLINER_CORE_RELEASE_REPO:-$DEFAULT_RELEASE_REPO}"
LOCAL_CORE_REPO="${DEADLINER_CORE_LOCAL_REPO:-$DEFAULT_CORE_REPO}"
GITHUB_API_ROOT="${DEADLINER_CORE_GITHUB_API_ROOT:-https://api.github.com}"
GITHUB_CONNECT_TIMEOUT="${DEADLINER_CORE_GITHUB_CONNECT_TIMEOUT:-10}"
GITHUB_MAX_TIME="${DEADLINER_CORE_GITHUB_MAX_TIME:-900}"
GITHUB_RETRY_COUNT="${DEADLINER_CORE_GITHUB_RETRY_COUNT:-3}"

DEST_XCFRAMEWORK="${IOS_REPO_ROOT}/Vendor/DeadlinerCore/ffi_uniffi.xcframework"
DEST_SWIFT_BINDING="${IOS_REPO_ROOT}/DeadlinerCoreSupport/Generated/ffi_uniffi.swift"

AUTH_TOKEN=""
GH_AVAILABLE="false"

resolve_github_token() {
  if [[ -n "${DEADLINER_CORE_GITHUB_TOKEN:-}" ]]; then
    printf '%s' "${DEADLINER_CORE_GITHUB_TOKEN}"
    return 0
  fi

  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    printf '%s' "${GITHUB_TOKEN}"
    return 0
  fi

  if command -v gh >/dev/null 2>&1; then
    gh auth token 2>/dev/null || true
    return 0
  fi

  return 0
}

detect_gh_auth() {
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

require_path() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    echo "error: missing required path: $path" >&2
    exit 1
  fi
}

ensure_tools() {
  command -v curl >/dev/null 2>&1 || {
    echo "error: curl is required" >&2
    exit 1
  }
  command -v python3 >/dev/null 2>&1 || {
    echo "error: python3 is required" >&2
    exit 1
  }
}

auth_hint() {
  cat >&2 <<'EOF'
hint: this repo is private, so release sync needs GitHub auth.
hint: set DEADLINER_CORE_GITHUB_TOKEN (recommended) or GITHUB_TOKEN before running this script.
hint: example:
hint:   export DEADLINER_CORE_GITHUB_TOKEN=ghp_xxx
EOF
}

has_cached_sync() {
  [[ -d "${DEST_XCFRAMEWORK}" && -f "${DEST_SWIFT_BINDING}" ]]
}

fallback_to_cached_sync() {
  local reason="$1"
  if has_cached_sync; then
    echo "warning: ${reason}" >&2
    echo "warning: failed to refresh iOS release artifact, falling back to existing synced files" >&2
    return 0
  fi

  echo "error: ${reason}" >&2
  echo "error: no usable cached iOS core files found in ${IOS_REPO_ROOT}" >&2
  return 1
}

clean_destinations() {
  rm -rf "${DEST_XCFRAMEWORK}"
  mkdir -p "$(dirname "${DEST_XCFRAMEWORK}")"
  mkdir -p "$(dirname "${DEST_SWIFT_BINDING}")"
}

patch_uniffi_swift() {
  local swift_file="$1"

  SWIFT_FILE="$swift_file" python3 - <<'PY'
from pathlib import Path
import os
import re

path = Path(os.environ["SWIFT_FILE"])
text = path.read_text()

declaration_pattern = re.compile(
    r"((?:fileprivate|private)\s+func\s+uniffiFutureContinuationCallback\s*\(\s*handle:\s*UInt64\s*,\s*pollResult:\s*Int8\s*\)\s*\{)",
    re.MULTILINE,
)
callsite_pattern = re.compile(
    r"(^\s*)uniffiFutureContinuationCallback,\s*$",
    re.MULTILINE,
)
wrapper = """fileprivate let uniffiFutureContinuationCallbackFn: UniffiRustFutureContinuationCallback = { handle, pollResult in
    uniffiFutureContinuationCallback(handle: handle, pollResult: pollResult)
}

"""

if "uniffiFutureContinuationCallbackFn" not in text:
    match = declaration_pattern.search(text)
    if match:
        text = text[:match.start()] + wrapper + match.group(1) + text[match.end():]

if callsite_pattern.search(text):
    text = callsite_pattern.sub(r"\1uniffiFutureContinuationCallbackFn,", text)
else:
    print(f"warning: future continuation callback callsite not found in {path}; skipping compatibility patch")

path.write_text(text)
PY
}

write_state_file() {
  local mode="$1"
  local source="$2"
  local tag="${3:-}"
  local commit="${4:-}"

  mkdir -p "$(dirname "${STATE_FILE}")"
  python3 - <<'PY' "${STATE_FILE}" "${mode}" "${source}" "${tag}" "${commit}"
from pathlib import Path
import json
import sys

state_path = Path(sys.argv[1])
mode = sys.argv[2]
source = sys.argv[3]
tag = sys.argv[4]
commit = sys.argv[5]

payload = {
    "mode": mode,
    "source": source,
}
if tag:
    payload["tag"] = tag
if commit:
    payload["commit"] = commit

state_path.write_text(json.dumps(payload, indent=2) + "\n")
PY
}

read_cached_commit() {
  python3 - <<'PY' "${STATE_FILE}"
from pathlib import Path
import json
import sys

state_path = Path(sys.argv[1])
if not state_path.exists():
    print("")
else:
    data = json.loads(state_path.read_text())
    print(data.get("commit", ""))
PY
}

sync_from_local_repo() {
  local core_repo="$1"
  local src_xcframework src_swift_binding

  src_xcframework="${core_repo}/dist/ios/ffi_uniffi.xcframework"
  src_swift_binding="${core_repo}/dist/ios/bindings/ffi_uniffi.swift"

  echo "==> Syncing Deadliner core iOS artifacts from local core repo"
  echo "    core repo: ${core_repo}"

  require_path "${src_xcframework}"
  require_path "${src_swift_binding}"

  clean_destinations
  cp -R "${src_xcframework}" "${DEST_XCFRAMEWORK}"
  cp "${src_swift_binding}" "${DEST_SWIFT_BINDING}"

  echo "==> Applying Swift callback compatibility patch"
  patch_uniffi_swift "${DEST_SWIFT_BINDING}"

  write_state_file "local" "${core_repo}"
}

fetch_release_metadata() {
  local response_file="$1"

  echo "==> Fetching release metadata"

  if [[ "${GH_AVAILABLE}" == "true" ]]; then
    gh api "repos/${RELEASE_REPO}/releases/tags/${RELEASE_TAG}" > "${response_file}"
    return 0
  fi

  local -a curl_args

  curl_args=(
    -fsSL
    --connect-timeout "${GITHUB_CONNECT_TIMEOUT}"
    --max-time "${GITHUB_MAX_TIME}"
    --retry "${GITHUB_RETRY_COUNT}"
    --retry-all-errors
    -H "Accept: application/vnd.github+json"
    -H "X-GitHub-Api-Version: 2022-11-28"
    -H "User-Agent: deadliner-core-ios-sync"
  )

  if [[ -n "${AUTH_TOKEN}" ]]; then
    curl_args+=(-H "Authorization: Bearer ${AUTH_TOKEN}")
  fi

  curl_args+=(
    "${GITHUB_API_ROOT}/repos/${RELEASE_REPO}/releases/tags/${RELEASE_TAG}"
    -o "${response_file}"
  )

  curl "${curl_args[@]}"
}

download_release_asset() {
  local metadata_file="$1"
  local output_file="$2"
  local asset_api_url

  if ! asset_api_url="$(python3 - <<'PY' "${metadata_file}" "${ARTIFACT_NAME}"
from pathlib import Path
import json
import sys

metadata_path = Path(sys.argv[1])
asset_name = sys.argv[2]

metadata = json.loads(metadata_path.read_text())
assets = metadata.get("assets", [])
asset_url = None
for asset in assets:
    if asset.get("name") == asset_name:
        asset_url = asset.get("url")
        break

if not asset_url:
    raise SystemExit(f"error: asset {asset_name} not found in release metadata")

print(asset_url)
PY
)"; then
    return 1
  fi

  echo "==> Downloading iOS release asset"

  if [[ "${GH_AVAILABLE}" == "true" ]]; then
    rm -f "${output_file}"
    gh release download "${RELEASE_TAG}" \
      --repo "${RELEASE_REPO}" \
      --pattern "${ARTIFACT_NAME}" \
      --output "${output_file}" \
      --clobber
    return 0
  fi

  local -a curl_args
  curl_args=(
    -fsSL
    --connect-timeout "${GITHUB_CONNECT_TIMEOUT}"
    --max-time "${GITHUB_MAX_TIME}"
    --retry "${GITHUB_RETRY_COUNT}"
    --retry-all-errors
    -H "Accept: application/octet-stream"
    -H "X-GitHub-Api-Version: 2022-11-28"
    -H "User-Agent: deadliner-core-ios-sync"
  )

  if [[ -n "${AUTH_TOKEN}" ]]; then
    curl_args+=(-H "Authorization: Bearer ${AUTH_TOKEN}")
  fi

  curl_args+=("${asset_api_url}" -o "${output_file}")
  curl "${curl_args[@]}"
}

extract_release_artifact() {
  local archive_file="$1"
  local extract_dir="$2"

  echo "==> Extracting iOS release archive"
  python3 - <<'PY' "${archive_file}" "${extract_dir}"
from pathlib import Path
import shutil
import sys
import zipfile

archive = Path(sys.argv[1])
extract_dir = Path(sys.argv[2])

if extract_dir.exists():
    shutil.rmtree(extract_dir)
extract_dir.mkdir(parents=True, exist_ok=True)

with zipfile.ZipFile(archive) as zf:
    zf.extractall(extract_dir)
PY
}

sync_from_release() {
  local metadata_file zip_file extract_dir cached_sha remote_sha

  mkdir -p "${CACHE_ROOT}" "$(dirname "${STATE_FILE}")"
  metadata_file="${CACHE_ROOT}/release-ios.json"
  zip_file="${CACHE_ROOT}/${ARTIFACT_NAME}"
  extract_dir="${CACHE_ROOT}/ios-unzipped"

  echo "==> Syncing Deadliner core iOS artifacts from GitHub release"
  echo "    repo: ${RELEASE_REPO}"
  echo "    tag: ${RELEASE_TAG}"

  if [[ -z "${AUTH_TOKEN}" ]]; then
    echo "warning: no GitHub token detected; private release access may fail." >&2
  fi

  if [[ "${GH_AVAILABLE}" == "true" ]]; then
    echo "==> GitHub CLI authenticated"
  elif command -v gh >/dev/null 2>&1; then
    echo "==> GitHub CLI detected but not authenticated for this shell"
  fi

  if ! fetch_release_metadata "${metadata_file}"; then
    auth_hint
    fallback_to_cached_sync "failed to fetch release metadata for ${RELEASE_REPO}@${RELEASE_TAG}"
    return $?
  fi

  if ! remote_sha="$(python3 - <<'PY' "${metadata_file}"
from pathlib import Path
import json
import re
import sys

metadata = json.loads(Path(sys.argv[1]).read_text())
body = metadata.get("body") or ""
match = re.search(r"Commit:\s*([0-9a-fA-F]{7,40})", body)
print(match.group(1) if match else metadata.get("target_commitish", "unknown"))
PY
)"; then
    fallback_to_cached_sync "failed to parse release metadata for ${RELEASE_REPO}@${RELEASE_TAG}"
    return $?
  fi

  cached_sha="$(read_cached_commit)"
  if [[ -n "${cached_sha}" && "${cached_sha}" == "${remote_sha}" && -d "${DEST_XCFRAMEWORK}" && -f "${DEST_SWIFT_BINDING}" ]]; then
    echo "==> iOS core artifacts already up to date at ${remote_sha}"
    return 0
  fi

  if ! download_release_asset "${metadata_file}" "${zip_file}"; then
    auth_hint
    fallback_to_cached_sync "failed to download ${ARTIFACT_NAME} from ${RELEASE_REPO}@${RELEASE_TAG}"
    return $?
  fi

  if ! extract_release_artifact "${zip_file}" "${extract_dir}"; then
    fallback_to_cached_sync "failed to extract ${zip_file}"
    return $?
  fi

  require_path "${extract_dir}/ios/ffi_uniffi.xcframework"
  require_path "${extract_dir}/ios/bindings/ffi_uniffi.swift"

  clean_destinations
  cp -R "${extract_dir}/ios/ffi_uniffi.xcframework" "${DEST_XCFRAMEWORK}"
  cp "${extract_dir}/ios/bindings/ffi_uniffi.swift" "${DEST_SWIFT_BINDING}"

  echo "==> Applying Swift callback compatibility patch"
  patch_uniffi_swift "${DEST_SWIFT_BINDING}"

  write_state_file "release" "${RELEASE_REPO}" "${RELEASE_TAG}" "${remote_sha}"
  echo "==> Synced iOS core artifacts at commit ${remote_sha}"
}

main() {
  ensure_tools
  AUTH_TOKEN="$(resolve_github_token)"
  if detect_gh_auth; then
    GH_AVAILABLE="true"
  fi

  case "${MODE}" in
    local)
      sync_from_local_repo "${LOCAL_CORE_REPO}"
      ;;
    release)
      sync_from_release
      ;;
    /*)
      sync_from_local_repo "${MODE}"
      ;;
    *)
      RELEASE_TAG="${MODE}"
      sync_from_release
      ;;
  esac

  echo "==> Synced:"
  echo "    xcframework -> ${DEST_XCFRAMEWORK}"
  echo "    swift binding -> ${DEST_SWIFT_BINDING}"
}

main "$@"
