#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="${RAYCAST_CHECKER:-$repo_root/scripts/check-raycast-beta.sh}"
updater="${RAYCAST_UPDATER:-$repo_root/scripts/update-raycast-beta-cask.sh}"
cask_file="${RAYCAST_CASK_FILE:-$repo_root/Casks/raycast@beta.rb}"
cask_path="${RAYCAST_CASK_PATH:-Casks/raycast@beta.rb}"
base_branch="${RAYCAST_BASE_BRANCH:-main}"
automation_branch="${RAYCAST_AUTOMATION_BRANCH:-automation/raycast-beta}"
repository="${GITHUB_REPOSITORY:-}"

if [[ -z "$repository" ]]; then
	repository="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
fi

eval "$(RAYCAST_CASK_FILE="$cask_file" "$checker" --format env)"

if [[ "$RAYCAST_UPDATE_AVAILABLE" == false ]]; then
	printf 'Raycast Beta is current at %s.\n' "$RAYCAST_CURRENT_VERSION"
	exit 0
fi

pr_updates_latest_version() {
	local pr_number="$1"
	local result

	while IFS= read -r result; do
		[[ "$result" == "true" ]] && return 0
	done < <(
		gh api "repos/${repository}/pulls/${pr_number}/files" \
			--jq ".[] | select(.filename == \"${cask_path}\") | (.patch // \"\" | contains(\"+  version \\\"${RAYCAST_LATEST_VERSION}\\\"\"))"
	)

	return 1
}

find_same_version_pr() {
	local pr_number

	while IFS= read -r pr_number; do
		[[ -z "$pr_number" ]] && continue
		if pr_updates_latest_version "$pr_number"; then
			printf '%s\n' "$pr_number"
			return 0
		fi
	done < <(gh pr list --state open --json number --jq '.[].number')

	return 1
}

same_version_pr="$(find_same_version_pr || true)"

if [[ -n "$same_version_pr" ]]; then
	printf 'Open PR #%s already updates Raycast Beta to %s.\n' "$same_version_pr" "$RAYCAST_LATEST_VERSION"
	exit 0
fi

automation_pr="$(gh pr list --state open --head "$automation_branch" --json number --jq '.[0].number // empty')"
pr_title="Update Raycast Beta to ${RAYCAST_LATEST_VERSION}"
pr_body="Updates Raycast Beta from ${RAYCAST_CURRENT_VERSION} to ${RAYCAST_LATEST_VERSION}.

DMG: ${RAYCAST_LATEST_DMG_URL}

This PR is managed by the daily Raycast Beta automation workflow."

git fetch origin "$base_branch"

if git ls-remote --exit-code --heads origin "$automation_branch" >/dev/null 2>&1; then
	git fetch origin "$automation_branch"
	git checkout -B "$automation_branch" "origin/$automation_branch"
else
	git checkout -B "$automation_branch" "origin/$base_branch"
fi

RAYCAST_CASK_FILE="$cask_file" "$updater"

if git diff --quiet -- "$cask_file"; then
	printf 'Raycast Beta cask already matches %s on %s.\n' "$RAYCAST_LATEST_VERSION" "$automation_branch"
else
	git add "$cask_file"
	git config user.name "github-actions[bot]"
	git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
	git commit -m "chore: update Raycast Beta to ${RAYCAST_LATEST_VERSION}"
	git push --set-upstream origin "$automation_branch"
fi

if [[ -n "$automation_pr" ]]; then
	gh pr edit "$automation_pr" --title "$pr_title" --body "$pr_body"
	printf 'Updated Raycast Beta automation PR #%s for %s.\n' "$automation_pr" "$RAYCAST_LATEST_VERSION"
else
	gh pr create --base "$base_branch" --head "$automation_branch" --title "$pr_title" --body "$pr_body"
	printf 'Created Raycast Beta automation PR for %s.\n' "$RAYCAST_LATEST_VERSION"
fi
