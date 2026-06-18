#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="${RAYCAST_CHECKER:-$repo_root/scripts/check-raycast-beta.sh}"
cask_file="${RAYCAST_CASK_FILE:-$repo_root/Casks/raycast@beta.rb}"

eval "$(RAYCAST_CASK_FILE="$cask_file" "$checker" --format env)"

if [[ "$RAYCAST_UPDATE_AVAILABLE" == false ]]; then
	printf 'Raycast Beta is current at %s.\n' "$RAYCAST_CURRENT_VERSION"
	exit 0
fi

dmg_file="$(mktemp)"
trap 'rm -f "$dmg_file"' EXIT

curl -fsSL --retry 3 --retry-delay 2 -o "$dmg_file" "$RAYCAST_LATEST_DMG_URL"
read -r sha256 _ < <(shasum -a 256 "$dmg_file")

ruby - "$cask_file" "$RAYCAST_LATEST_VERSION" "$sha256" <<'RUBY'
path, version, sha256 = ARGV
content = File.read(path)

unless content.sub!(/^(\s*version\s+)"[^"]+"/, "\\1\"#{version}\"")
  abort("Unable to update version in #{path}")
end

unless content.sub!(/^(\s*sha256\s+)"[^"]+"/, "\\1\"#{sha256}\"")
  abort("Unable to update sha256 in #{path}")
end

File.write(path, content)
RUBY

printf 'Updated Raycast Beta to %s with sha256 %s.\n' "$RAYCAST_LATEST_VERSION" "$sha256"
