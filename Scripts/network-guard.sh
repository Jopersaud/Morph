#!/bin/bash
#
# network-guard.sh — fail the build if Morph grows a network code path.
#
# Morph converts files locally and makes no network calls at all (SPEC §7).
# That promise is only worth something if something checks it, so this runs in
# CI and in `make lint`.
#
# It looks for three things:
#   1. networking symbols in source code (URLSession, NWConnection, CFNetwork,
#      BSD sockets, WebKit)
#   2. network entitlements and related Info.plist keys
#   3. analytics and crash-reporting SDKs, which SPEC §7 also rules out
#
# A genuine false positive can be silenced per line:
#
#     let connection = something.connect()  // network-guard:allow local IPC only
#
# Allowances are printed in the report, so they show up in review rather than
# quietly accumulating.

set -euo pipefail

cd "$(dirname "$0")/.."

# Paths allowed to name these symbols: this script, the CI workflow that runs
# it, the docs that explain the rule, and third-party code under Vendor/, which
# is not Morph's own code path.
#
# Markdown is never scanned — only the source and plist extensions below — so
# the prose in README.md and SPEC.md needs no exemption.
EXCLUDED_PATHS=(
	"Scripts/"
	".github/"
	"docs/"
	"Vendor/"
)

SOURCE_EXTENSIONS="swift|m|mm|h|hpp|c|cc|cpp"
PLIST_EXTENSIONS="entitlements|plist"

# 1. Networking symbols.
SYMBOL_PATTERN='\b(URLSession|NSURLSession|NSURLConnection|URLRequest|URLCredential)\b'
SYMBOL_PATTERN+='|\b(NWConnection|NWListener|NWBrowser|NWPath|NWEndpoint|nw_connection|nw_socket)\b'
SYMBOL_PATTERN+='|\b(CFNetwork|CFSocket|CFHost|CFHTTPMessage|CFURLRequest|CFFTP)'
SYMBOL_PATTERN+='|^[[:space:]]*(@_exported[[:space:]]+)?import[[:space:]]+(Network|CFNetwork|WebKit|NetworkExtension)\b'
SYMBOL_PATTERN+='|\b(WKWebView|WKWebViewConfiguration)\b'
SYMBOL_PATTERN+='|\b(socket|connect|bind|listen|accept|sendto|recvfrom|sendmsg|recvmsg'
SYMBOL_PATTERN+='|getaddrinfo|gethostbyname|setsockopt|inet_addr|inet_pton|inet_ntop)[[:space:]]*\('
SYMBOL_PATTERN+='|\b(sockaddr|sockaddr_in|sockaddr_in6|AF_INET|AF_INET6|SOCK_STREAM|SOCK_DGRAM)\b'

# 2. Entitlements and Info.plist keys that would grant or configure network
#    access.
PLIST_PATTERN='com\.apple\.security\.network\.(client|server)'
PLIST_PATTERN+='|NSAppTransportSecurity'
PLIST_PATTERN+='|NSLocalNetworkUsageDescription'
PLIST_PATTERN+='|NSBonjourServices'

# 3. Analytics, telemetry and crash reporting.
SDK_PATTERN='^[[:space:]]*import[[:space:]]+(Sentry|Firebase|FirebaseCore|FirebaseAnalytics'
SDK_PATTERN+='|Crashlytics|FirebaseCrashlytics|Mixpanel|Amplitude|Bugsnag|PostHog|Segment'
SDK_PATTERN+='|Analytics|AppCenter|AppCenterAnalytics|AppCenterCrashes|TelemetryDeck|Datadog)\b'

violations=0
allowances=0
scanned=0

is_excluded() {
	local file="$1"
	for prefix in "${EXCLUDED_PATHS[@]}"; do
		if [[ "$file" == "$prefix"* ]]; then
			return 0
		fi
	done
	return 1
}

# Tracked files if this is a git checkout, everything otherwise, so the guard
# works on a tarball, and on a repo with nothing committed yet.
list_files() {
	local tracked=""
	if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		tracked="$(git ls-files)"
	fi
	if [[ -n "$tracked" ]]; then
		printf '%s\n' "$tracked"
	else
		find . -type f -not -path './.git/*' -not -path './build/*' \
			-not -path '*/.build/*' -not -path '*.xcodeproj/*' | sed 's|^\./||'
	fi
}

scan() {
	local file="$1" pattern="$2" label="$3"

	# grep -n prints "line:text"; no match is not an error here.
	local matches
	matches="$(grep -nE "$pattern" "$file" 2>/dev/null || true)"
	[[ -z "$matches" ]] && return 0

	while IFS= read -r match; do
		[[ -z "$match" ]] && continue
		local line_number="${match%%:*}"
		local text="${match#*:}"

		if [[ "$text" == *"network-guard:allow"* ]]; then
			local reason="${text#*network-guard:allow}"
			printf 'allowed  %s:%s: %s\n' "$file" "$line_number" "${reason# }"
			allowances=$((allowances + 1))
			continue
		fi

		# Strip the leading indentation so the quoted line reads cleanly.
		local trimmed="${text#"${text%%[![:space:]]*}"}"
		printf '%s:%s: error: %s\n' "$file" "$line_number" "$label"
		printf '        %s\n' "$trimmed"
		violations=$((violations + 1))
	done <<<"$matches"
}

while IFS= read -r file; do
	[[ -f "$file" ]] || continue
	is_excluded "$file" && continue

	case "$file" in
	*.*)
		extension="${file##*.}"
		;;
	*)
		continue
		;;
	esac

	if [[ "$extension" =~ ^($SOURCE_EXTENSIONS)$ ]]; then
		scanned=$((scanned + 1))
		scan "$file" "$SYMBOL_PATTERN" "networking API in local-only code (SPEC §7)"
		scan "$file" "$SDK_PATTERN" "analytics or crash-reporting SDK (SPEC §7)"
	elif [[ "$extension" =~ ^($PLIST_EXTENSIONS)$ ]]; then
		scanned=$((scanned + 1))
		scan "$file" "$PLIST_PATTERN" "network entitlement or key (SPEC §7)"
	fi
done < <(list_files)

echo "network guard: scanned $scanned files, $violations violations, $allowances allowances"

# A guard that scans nothing proves nothing, so treat that as a failure rather
# than a pass.
if ((scanned == 0)); then
	echo "error: no source files were scanned — the guard is misconfigured" >&2
	exit 1
fi

if ((violations > 0)); then
	cat <<'EOF'

Morph has no network code paths (SPEC §7). If you believe an exception is
justified, ask first, then annotate the line:

    // network-guard:allow <why this is not a network call>

EOF
	exit 1
fi
