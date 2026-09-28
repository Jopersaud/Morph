#!/bin/bash
#
# test-packages.sh — run `swift test` in every local package.
#
# The packages hold the converter logic and its unit tests. They build without
# Xcode's project machinery, so this is the fast inner loop; `xcodebuild test`
# covers the app, the extension and the UI smoke test.

set -euo pipefail

cd "$(dirname "$0")/.."

action="${1:-test}"

packages="$(find Packages -maxdepth 3 -name Package.swift | sort)"

if [[ -z "$packages" ]]; then
	echo "error: no packages found under Packages/" >&2
	exit 1
fi

failures=0

while IFS= read -r manifest; do
	package_dir="$(dirname "$manifest")"
	printf '\n▸ swift %s — %s\n' "$action" "$package_dir"
	if ! swift "$action" --package-path "$package_dir"; then
		failures=$((failures + 1))
	fi
done <<<"$packages"

echo
if ((failures > 0)); then
	echo "packages: $failures package(s) failed"
	exit 1
fi
echo "packages: all green"
