#!/bin/bash
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/overview-checks.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
python3 - "$repo_dir" "$check_dir" <<'PY'
from pathlib import Path
import sys
source = (Path(sys.argv[1]) / 'Deadliner/Core/Domain/Models/AIModels.swift').read_text()
start = source.index('nonisolated public struct MonthlyAnalysisResult:')
end = source.index('\n}', start) + 2
(Path(sys.argv[2]) / 'MonthlyAnalysisModel.swift').write_text('import Foundation\n' + source[start:end])
PY
swiftc -swift-version 6 -default-isolation MainActor -module-cache-path "$check_dir/module-cache" -parse-as-library \
  "$repo_dir/Deadliner/Features/Overview/OverviewPeriod.swift" \
  "$repo_dir/Deadliner/Data/Repositories/Overview/MonthlyInsightRepository.swift" \
  "$check_dir/MonthlyAnalysisModel.swift" \
  "$repo_dir/scripts/validation/OverviewDashboardChecks.swift" -o "$check_dir/checks"
"$check_dir/checks"
