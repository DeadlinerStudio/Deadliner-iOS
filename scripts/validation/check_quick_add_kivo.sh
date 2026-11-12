#!/bin/bash
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/quick-add-kivo.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
bundle_dir="$check_dir/Checks.app/Contents"
mkdir -p "$bundle_dir/MacOS" "$bundle_dir/Resources"
for source_name in QuickAddBackend QuickAddDraft QuickAddModelService; do
  sed '/^import Shared$/d' "$repo_dir/Deadliner/Features/Main/Sheets/$source_name.swift" > "$check_dir/$source_name.swift"
done
for resource_name in quick-add-model quick-add-model-en quick-add-model-kivo-preview; do
  echo '{}' > "$bundle_dir/Resources/$resource_name.json"
done
cat > "$bundle_dir/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>dev.codex.QuickAddChecks</string><key>CFBundleExecutable</key><string>Checks</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
swiftc -swift-version 5 -module-cache-path "$check_dir/module-cache" -parse-as-library \
  "$check_dir/QuickAddBackend.swift" "$check_dir/QuickAddDraft.swift" "$check_dir/QuickAddModelService.swift" \
  "$repo_dir/scripts/validation/QuickAddKivoChecks.swift" -o "$bundle_dir/MacOS/Checks"
"$bundle_dir/MacOS/Checks"
