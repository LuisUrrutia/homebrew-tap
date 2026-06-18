#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$repo_root/scripts/check-raycast-beta.sh"
updater="$repo_root/scripts/update-raycast-beta-cask.sh"
automation="$repo_root/scripts/automate-raycast-beta-pr.sh"
fixtures="$repo_root/tests/fixtures"
tests_run=0

fail() {
	printf 'not ok - %s\n' "$1" >&2
	exit 1
}

assert_contains() {
	local haystack="$1"
	local needle="$2"

	[[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

file_url() {
	ruby -e 'puts "file://#{File.expand_path(ARGV.fetch(0))}"' "$1"
}

run_case() {
	local name="$1"
	shift

	"$@"
	tests_run=$((tests_run + 1))
	printf 'ok %d - %s\n' "$tests_run" "$name"
}

copy_cask() {
	local target="$1"

	cp "$fixtures/raycast-old.rb" "$target"
}

cask_version() {
	ruby -e 'puts File.read(ARGV.fetch(0)).match(/^\s*version\s+"([^"]+)"/)[1]' "$1"
}

cask_sha256() {
	ruby -e 'puts File.read(ARGV.fetch(0)).match(/^\s*sha256\s+"([^"]+)"/)[1]' "$1"
}

test_current_version_exits_zero() {
	local tmp cask output

	tmp="$(mktemp -d)"
	cask="$tmp/raycast.rb"
	copy_cask "$cask"

	output="$(
		RAYCAST_CASK_FILE="$cask" \
			RAYCAST_NEW_URL="$(file_url "$fixtures/raycast-current.html")" \
			"$checker"
	)"

	assert_contains "$output" "Raycast Beta is current at 0.65.1.0,66eacbc22e."
}

test_env_output_reports_newer_version() {
	local tmp cask output

	tmp="$(mktemp -d)"
	cask="$tmp/raycast.rb"
	copy_cask "$cask"

	output="$(
		RAYCAST_CASK_FILE="$cask" \
			RAYCAST_NEW_URL="$(file_url "$fixtures/raycast-newer.html")" \
			RAYCAST_DMG_BASE_URL="$(file_url "$fixtures")" \
			"$checker" --format env
	)"

	eval "$output"

	[[ "$RAYCAST_CURRENT_VERSION" == "0.65.1.0,66eacbc22e" ]] || fail "expected current version in env output"
	[[ "$RAYCAST_LATEST_VERSION" == "0.66.0.0,abcdef1234" ]] || fail "expected latest version in env output"
	[[ "$RAYCAST_UPDATE_AVAILABLE" == "true" ]] || fail "expected update flag in env output"
	[[ "$RAYCAST_LATEST_DMG_URL" == "$(file_url "$fixtures")/Raycast_Beta_0.66.0.0_abcdef1234_arm64.dmg" ]] || fail "expected latest DMG URL in env output"
}

test_fail_on_update_exits_ten() {
	local tmp cask status

	tmp="$(mktemp -d)"
	cask="$tmp/raycast.rb"
	copy_cask "$cask"

	set +e
	RAYCAST_CASK_FILE="$cask" \
		RAYCAST_NEW_URL="$(file_url "$fixtures/raycast-newer.html")" \
		"$checker" --fail-on-update >/dev/null 2>&1
	status=$?
	set -e

	[[ "$status" -eq 10 ]] || fail "expected --fail-on-update to exit 10, got $status"
}

test_missing_dmg_exits_nonzero() {
	local tmp cask status

	tmp="$(mktemp -d)"
	cask="$tmp/raycast.rb"
	copy_cask "$cask"

	set +e
	RAYCAST_CASK_FILE="$cask" \
		RAYCAST_NEW_URL="$(file_url "$fixtures/raycast-missing.html")" \
		"$checker" >/dev/null 2>&1
	status=$?
	set -e

	[[ "$status" -ne 0 ]] || fail "expected missing DMG page to fail"
}

test_update_rewrites_version_and_sha() {
	local tmp cask expected_sha

	tmp="$(mktemp -d)"
	cask="$tmp/raycast.rb"
	copy_cask "$cask"
	read -r expected_sha _ < <(shasum -a 256 "$fixtures/Raycast_Beta_0.66.0.0_abcdef1234_arm64.dmg")

	RAYCAST_CASK_FILE="$cask" \
		RAYCAST_NEW_URL="$(file_url "$fixtures/raycast-newer.html")" \
		RAYCAST_DMG_BASE_URL="$(file_url "$fixtures")" \
		"$updater" >/dev/null

	[[ "$(cask_version "$cask")" == "0.66.0.0,abcdef1234" ]] || fail "expected cask version to update"
	[[ "$(cask_sha256 "$cask")" == "$expected_sha" ]] || fail "expected cask sha256 to update"
	ruby -c "$cask" >/dev/null
}

write_fake_gh() {
	local bin_dir="$1"

	cat >"$bin_dir/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail

printf 'gh %s\n' "$*" >>"$GH_LOG"

if [[ "$1 $2" == "pr list" ]]; then
  if [[ "$*" == *"--head automation/raycast-beta"* ]]; then
    printf '%s\n' "${GH_AUTOMATION_PR:-}"
  else
    printf '%s\n' "${GH_OPEN_PRS:-}"
  fi
  exit 0
fi

if [[ "$1" == "api" ]]; then
  printf '%s\n' "${GH_PR_FILE_MATCH:-false}"
  exit 0
fi

if [[ "$1 $2" == "pr edit" || "$1 $2" == "pr create" ]]; then
  exit 0
fi

printf 'unexpected gh call: %s\n' "$*" >&2
exit 1
GH
	chmod +x "$bin_dir/gh"
}

write_fake_git() {
	local bin_dir="$1"

	cat >"$bin_dir/git" <<'GIT'
#!/usr/bin/env bash
set -euo pipefail

printf 'git %s\n' "$*" >>"$GIT_LOG"

if [[ "$1" == "ls-remote" ]]; then
  exit "${GIT_LS_REMOTE_STATUS:-0}"
fi

if [[ "$1 $2" == "diff --quiet" ]]; then
  exit "${GIT_DIFF_STATUS:-1}"
fi

exit 0
GIT
	chmod +x "$bin_dir/git"
}

test_automation_skips_same_version_pr() {
	local tmp cask bin_dir output

	tmp="$(mktemp -d)"
	cask="$tmp/raycast.rb"
	bin_dir="$tmp/bin"
	mkdir -p "$bin_dir"
	copy_cask "$cask"
	write_fake_gh "$bin_dir"
	write_fake_git "$bin_dir"

	output="$(
		PATH="$bin_dir:$PATH" \
			GH_LOG="$tmp/gh.log" \
			GIT_LOG="$tmp/git.log" \
			GH_OPEN_PRS="12" \
			GH_PR_FILE_MATCH="true" \
			GITHUB_REPOSITORY="LuisUrrutia/homebrew-tap" \
			RAYCAST_CASK_FILE="$cask" \
			RAYCAST_NEW_URL="$(file_url "$fixtures/raycast-newer.html")" \
			RAYCAST_DMG_BASE_URL="$(file_url "$fixtures")" \
			"$automation"
	)"

	assert_contains "$output" "Open PR #12 already updates Raycast Beta to 0.66.0.0,abcdef1234."
	[[ ! -s "$tmp/git.log" ]] || fail "expected same-version PR to skip git changes"
}

test_automation_updates_existing_bot_pr() {
	local tmp cask bin_dir expected_sha gh_log git_log

	tmp="$(mktemp -d)"
	cask="$tmp/raycast.rb"
	bin_dir="$tmp/bin"
	gh_log="$tmp/gh.log"
	git_log="$tmp/git.log"
	mkdir -p "$bin_dir"
	copy_cask "$cask"
	write_fake_gh "$bin_dir"
	write_fake_git "$bin_dir"
	read -r expected_sha _ < <(shasum -a 256 "$fixtures/Raycast_Beta_0.66.0.0_abcdef1234_arm64.dmg")

	PATH="$bin_dir:$PATH" \
		GH_LOG="$gh_log" \
		GIT_LOG="$git_log" \
		GH_OPEN_PRS="7" \
		GH_PR_FILE_MATCH="false" \
		GH_AUTOMATION_PR="7" \
		GITHUB_REPOSITORY="LuisUrrutia/homebrew-tap" \
		RAYCAST_CASK_FILE="$cask" \
		RAYCAST_NEW_URL="$(file_url "$fixtures/raycast-newer.html")" \
		RAYCAST_DMG_BASE_URL="$(file_url "$fixtures")" \
		"$automation" >/dev/null

	[[ "$(cask_version "$cask")" == "0.66.0.0,abcdef1234" ]] || fail "expected automation to update cask version"
	[[ "$(cask_sha256 "$cask")" == "$expected_sha" ]] || fail "expected automation to update cask sha"
	assert_contains "$(<"$gh_log")" "gh pr edit 7 --title Update Raycast Beta to 0.66.0.0,abcdef1234"
	assert_contains "$(<"$git_log")" "git push --set-upstream origin automation/raycast-beta"
}

test_automation_creates_new_bot_pr() {
	local tmp cask bin_dir gh_log git_log

	tmp="$(mktemp -d)"
	cask="$tmp/raycast.rb"
	bin_dir="$tmp/bin"
	gh_log="$tmp/gh.log"
	git_log="$tmp/git.log"
	mkdir -p "$bin_dir"
	copy_cask "$cask"
	write_fake_gh "$bin_dir"
	write_fake_git "$bin_dir"

	PATH="$bin_dir:$PATH" \
		GH_LOG="$gh_log" \
		GIT_LOG="$git_log" \
		GH_OPEN_PRS="" \
		GH_PR_FILE_MATCH="false" \
		GH_AUTOMATION_PR="" \
		GIT_LS_REMOTE_STATUS="2" \
		GITHUB_REPOSITORY="LuisUrrutia/homebrew-tap" \
		RAYCAST_CASK_FILE="$cask" \
		RAYCAST_NEW_URL="$(file_url "$fixtures/raycast-newer.html")" \
		RAYCAST_DMG_BASE_URL="$(file_url "$fixtures")" \
		"$automation" >/dev/null

	[[ "$(cask_version "$cask")" == "0.66.0.0,abcdef1234" ]] || fail "expected new PR automation to update cask version"
	assert_contains "$(<"$gh_log")" "gh pr create --base main --head automation/raycast-beta --title Update Raycast Beta to 0.66.0.0,abcdef1234"
	assert_contains "$(<"$git_log")" "git checkout -B automation/raycast-beta origin/main"
}

run_case "current version exits zero" test_current_version_exits_zero
run_case "env output reports newer version" test_env_output_reports_newer_version
run_case "fail on update exits ten" test_fail_on_update_exits_ten
run_case "missing dmg exits nonzero" test_missing_dmg_exits_nonzero
run_case "update rewrites version and sha" test_update_rewrites_version_and_sha
run_case "automation skips same-version PR" test_automation_skips_same_version_pr
run_case "automation updates existing bot PR" test_automation_updates_existing_bot_pr
run_case "automation creates new bot PR" test_automation_creates_new_bot_pr

printf '1..%d\n' "$tests_run"
