#!/usr/bin/env bash

set -euo pipefail

new_url="${RAYCAST_NEW_URL:-https://www.raycast.com/new}"
cask_file="${RAYCAST_CASK_FILE:-Casks/raycast@beta.rb}"
dmg_base_url="${RAYCAST_DMG_BASE_URL:-https://x-r2.raycast-releases.com}"
fail_on_update=false
output_format="human"

usage() {
	cat <<'USAGE'
Usage: scripts/check-raycast-beta.sh [--fail-on-update] [--format human|env]

Checks https://www.raycast.com/new for the latest Raycast Beta arm64 DMG and
compares it with Casks/raycast@beta.rb.

Options:
  --fail-on-update   Exit with status 10 when a newer DMG is found.
  --format human|env Output human text or shell-safe environment values.
  -h, --help         Show this help.
USAGE
}

while (($#)); do
	case "$1" in
	--fail-on-update)
		fail_on_update=true
		;;
	--format)
		shift
		output_format="${1:-}"
		if [[ "$output_format" != "human" && "$output_format" != "env" ]]; then
			printf 'Invalid --format value: %s\n' "$output_format" >&2
			usage >&2
			exit 2
		fi
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		printf 'Unknown argument: %s\n' "$1" >&2
		usage >&2
		exit 2
		;;
	esac
	shift
done

github_notice() {
	local title="$1"
	local message="$2"

	if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
		printf '::notice title=%s::%s\n' "$title" "$message"
	fi
}

github_summary() {
	local message="$1"

	if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
		printf '%b\n' "$message" >>"$GITHUB_STEP_SUMMARY"
	fi
}

print_env() {
	local name="$1"
	local value="$2"

	printf '%s=%q\n' "$name" "$value"
}

if [[ ! -f "$cask_file" ]]; then
	printf 'Cask file not found: %s\n' "$cask_file" >&2
	exit 2
fi

current_version="$(
	ruby - "$cask_file" <<'RUBY'
path = ARGV.fetch(0)
content = File.read(path)
match = content.match(/^\s*version\s+"([^"]+)"/)
abort("Unable to find cask version in #{path}") unless match
puts match[1]
RUBY
)"

page="$(curl -fsSL --retry 3 --retry-delay 2 "$new_url")"

latest_version="$(
	ruby -e '
require "rubygems"

page = STDIN.read
matches = page.scan(/Raycast[._-]Beta[._-]v?(\d+(?:\.\d+)+)[._-]([0-9a-f]+)[._-]arm64\.dmg/i)
source_url = ENV.fetch(%q[RAYCAST_NEW_URL], %q[https://www.raycast.com/new])

if matches.empty?
  warn "Unable to find Raycast Beta arm64 DMG in #{source_url}"
  exit 1
end

latest = matches.max_by { |version, _build| Gem::Version.new(version) }
puts "#{latest[0]},#{latest[1]}"
' <<<"$page"
)"

dmg_base_url="${dmg_base_url%/}"
latest_release="${latest_version%,*}"
latest_build="${latest_version#*,}"
latest_dmg_url="${dmg_base_url}/Raycast_Beta_${latest_release}_${latest_build}_arm64.dmg"
update_available=false

if [[ "$latest_version" != "$current_version" ]]; then
	update_available=true
fi

if [[ "$output_format" == "env" ]]; then
	print_env "RAYCAST_CURRENT_VERSION" "$current_version"
	print_env "RAYCAST_LATEST_VERSION" "$latest_version"
	print_env "RAYCAST_LATEST_RELEASE" "$latest_release"
	print_env "RAYCAST_LATEST_BUILD" "$latest_build"
	print_env "RAYCAST_LATEST_DMG_URL" "$latest_dmg_url"
	print_env "RAYCAST_UPDATE_AVAILABLE" "$update_available"

	if [[ "$fail_on_update" == true && "$update_available" == true ]]; then
		exit 10
	fi
	exit 0
fi

if [[ "$update_available" == false ]]; then
	message="Raycast Beta is current at ${current_version}."
	printf '%s\n' "$message"
	github_notice "Raycast Beta current" "$message"
	github_summary "## Raycast Beta check\n\n${message}"
	exit 0
fi

message="Raycast Beta update available: ${current_version} -> ${latest_version}. DMG: ${latest_dmg_url}"
printf '%s\n' "$message"
github_notice "Raycast Beta update available" "$message"
github_summary "## Raycast Beta update available\n\n- Current cask: \`${current_version}\`\n- Latest DMG: \`${latest_version}\`\n- URL: ${latest_dmg_url}"

if [[ "$fail_on_update" == true ]]; then
	exit 10
fi
