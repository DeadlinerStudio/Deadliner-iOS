#!/bin/sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
case "${DEADLINER_CORE_SOURCE:-package}" in
  package) exec /usr/bin/env python3 "$root/scripts/core_package.py" ios "$root/Vendor/KMP/shared.xcframework" --lock "$root/core-package.lock.json" ;;
  local) exec "${DEADLINER_CORE_DIR:-$root/../DeadlinerCore}/runscript/buildAndDeploy.sh" --skip-android --skip-harmony --configuration "${CONFIGURATION:-Release}" --ios-repo "$root" ;;
  *) echo "DEADLINER_CORE_SOURCE must be package or local" >&2; exit 2 ;;
esac
