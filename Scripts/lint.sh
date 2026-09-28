#!/bin/bash
#
# lint.sh — formatting and architecture checks.
#
# Runs in CI and from `make lint`, alongside Scripts/network-guard.sh.
#
#   1. swift-format, in strict mode, over every Swift file
#   2. the Finder Sync extension links ConversionKit and nothing else
#      (SPEC §6, §14)

set -euo pipefail

cd "$(dirname "$0")/.."

SWIFT_SOURCE_DIRS=(Apps Packages Tests)
ENGINE_PACKAGES="ImageEngine|MediaEngine|DocumentEngine|ArchiveEngine|MorphIntents"

failures=0

note() { printf '\n▸ %s\n' "$1"; }

note "swift-format"
if swift format lint --strict --recursive "${SWIFT_SOURCE_DIRS[@]}"; then
	echo "  formatting is clean"
else
	echo "  error: run \`make format\` to fix the findings above"
	failures=$((failures + 1))
fi

note "Finder Sync extension stays thin"

# The extension is sandboxed and must never do conversion work, so it must not
# import an engine.
if imports="$(grep -rnE "^[[:space:]]*import[[:space:]]+($ENGINE_PACKAGES)\b" \
	Apps/MorphFinderSync 2>/dev/null)"; then
	echo "  error: the Finder Sync extension imports an engine package:"
	while IFS= read -r line; do
		printf '    %s\n' "$line"
	done <<<"$imports"
	failures=$((failures + 1))
else
	echo "  no engine imports in Apps/MorphFinderSync"
fi

# Same rule, one level up: the Xcode target must not depend on an engine.
finder_sync_block="$(awk '
	/^  MorphFinderSync:/ { inside = 1; next }
	inside && /^  [A-Za-z]/ { inside = 0 }
	inside { print }
' project.yml)"

if [[ -z "$finder_sync_block" ]]; then
	echo "  error: no MorphFinderSync target found in project.yml"
	failures=$((failures + 1))
elif echo "$finder_sync_block" | grep -qE "package:[[:space:]]*($ENGINE_PACKAGES)\b"; then
	echo "  error: the MorphFinderSync target in project.yml depends on an engine package"
	failures=$((failures + 1))
else
	echo "  no engine dependencies in the MorphFinderSync target"
fi

note "shell scripts"
if command -v shellcheck >/dev/null 2>&1; then
	if shellcheck Scripts/*.sh; then
		echo "  shellcheck is clean"
	else
		failures=$((failures + 1))
	fi
else
	# Not installed everywhere; a syntax check is better than nothing.
	for script in Scripts/*.sh; do
		bash -n "$script" || failures=$((failures + 1))
	done
	echo "  shellcheck not installed; syntax-checked with bash -n"
fi

echo
if ((failures > 0)); then
	echo "lint: $failures check(s) failed"
	exit 1
fi
echo "lint: all checks passed"
