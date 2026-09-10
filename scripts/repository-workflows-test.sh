#!/bin/sh
set -eu

generation_script=$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")
update_script=$(cd "$(dirname "$2")" && pwd -P)/$(basename "$2")
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT HUP INT TERM
fake_bin=$test_root/bin
mkdir -p "$fake_bin" "$test_root/home-current/home-files/.config/wonkoos" "$test_root/home-legacy"
printf '%s\n' 1111111111111111111111111111111111111111-dirty \
	>"$test_root/home-current/home-files/.config/wonkoos/revision"

cat >"$fake_bin/nixos-rebuild" <<'EOF'
#!/bin/sh
test "$1" = list-generations
printf '%s\n' \
	'Generation  Build-date           NixOS version  Kernel  Configuration Revision  Specialisation  Current' \
	'2           2026-09-10 12:00:00  26.05          7.0.1   2222222222222222222222222222222222222222  []  False' \
	'1           2026-09-09 11:00:00  26.05          7.0.1   Unknown                                   []  True'
EOF
cat >"$fake_bin/home-manager" <<'EOF'
#!/bin/sh
test "$1" = generations
printf '%s\n' \
	"2026-09-10 12:01 : id 4 -> $TEST_ROOT/home-current (current)" \
	"2026-09-09 11:01 : id 3 -> $TEST_ROOT/home-legacy"
EOF
cat >"$fake_bin/gh" <<'EOF'
#!/bin/sh
case "$1 $2" in
auth\ status)
	exit 0
	;;
pr\ create)
	printf '%s\n' "$*" >>"$GH_LOG"
	printf '%s\n' https://github.com/bhechinger/WonkoOS/pull/99
	exit 0
	;;
pr\ view)
	printf '%s\n' "$*" >>"$GH_LOG"
	branch=$(git branch --show-current)
	main=$(git ls-remote origin refs/heads/main | awk '{ print $1 }')
	head=$(git ls-remote origin "refs/heads/$branch" | awk '{ print $1 }')
	if [ -n "$head" ] && [ "$main" = "$head" ]; then
		printf '%s\n' MERGED
	else
		printf '%s\n' OPEN
	fi
	exit 0
	;;
esac
case "$*" in
*1111111111111111111111111111111111111111*)
	printf '%s\n' "$*" >>"$GH_LOG"
	printf '%s\n' '#7,#9'
	;;
*2222222222222222222222222222222222222222*)
	printf '%s\n' "$*" >>"$GH_LOG"
	exit 1
	;;
esac
EOF
cat >"$fake_bin/nix" <<'EOF'
#!/bin/sh
case "$*" in
'flake update')
	case "${NIX_MODE:-change}" in
	change | check-fail | check-rewrite)
		printf '%s\n' updated >>flake.lock
		;;
	extra)
		printf '%s\n' updated >>flake.lock
		printf '%s\n' unexpected >unexpected-file
		;;
	nochange)
		;;
	esac
	;;
'flake check --all-systems --no-build --no-update-lock-file')
	printf '%s %s\n' "$*" "$(git rev-parse HEAD)" >>"$NIX_LOG"
	if [ "${NIX_MODE:-change}" = check-rewrite ]; then
		printf '%s\n' rewritten-after-commit >>flake.lock
	fi
	test "${NIX_MODE:-change}" != check-fail
	;;
*)
	printf 'Unexpected nix invocation: %s\n' "$*" >&2
	exit 1
	;;
esac
EOF
cat >"$fake_bin/date" <<'EOF'
#!/bin/sh
test "$*" = '-u +%Y%m%d-%H%M%S'
printf '%s\n' 20260910-120000
EOF
chmod +x "$fake_bin"/*

GH_LOG=$test_root/generation-gh.log
TEST_ROOT=$test_root
export GH_LOG TEST_ROOT
: >"$GH_LOG"
PATH="$fake_bin:$PATH" sh "$generation_script" deepthought >"$test_root/generations"
grep -Fq 'nixos 2' "$test_root/generations"
grep -Fq '2222222222222222222222222222222222222222' "$test_root/generations"
grep -Fq 'unavailable' "$test_root/generations"
grep -Fq 'nixos 1' "$test_root/generations"
grep -Fq 'legacy' "$test_root/generations"
grep -Fq 'home  4' "$test_root/generations"
grep -Fq '#7,#9 + dirty' "$test_root/generations"
test "$(grep -c 1111111111111111111111111111111111111111 "$GH_LOG")" -eq 1
if PATH="$fake_bin:$PATH" sh "$generation_script" unknown >/dev/null 2>&1; then
	printf 'generation script accepted an unsupported host\n' >&2
	exit 1
fi

new_repo() {
	name=$1
	origin=$test_root/$name-origin.git
	seed=$test_root/$name-seed
	work=$test_root/$name-work
	git init --bare -q --initial-branch=main "$origin"
	git init -q -b main "$seed"
	git -C "$seed" config user.name Test
	git -C "$seed" config user.email test@example.invalid
	git -C "$seed" config commit.gpgsign false
	printf '%s\n' base >"$seed/flake.lock"
	git -C "$seed" add flake.lock
	git -C "$seed" commit -q -m base
	git -C "$seed" remote add origin "$origin"
	git -C "$seed" push -q -u origin main
	git clone -q "$origin" "$work"
	git -C "$work" config user.name Test
	git -C "$work" config user.email test@example.invalid
	git -C "$work" config commit.gpgsign false
	TEST_REPO=$work
}

run_update() {
	(
		cd "$TEST_REPO"
		PATH="$fake_bin:$PATH" NIX_MODE=$1 GH_LOG=$GH_LOG NIX_LOG=$NIX_LOG sh "$update_script"
	)
}

GH_LOG=$test_root/update-gh.log
NIX_LOG=$test_root/update-nix.log
export GH_LOG NIX_LOG

new_repo success
: >"$GH_LOG"
: >"$NIX_LOG"
run_update change
test "$(git -C "$TEST_REPO" branch --show-current)" = main
test -z "$(git -C "$TEST_REPO" for-each-ref --format='%(refname:short)' 'refs/heads/feat/update-flake-lock-*')"
test -z "$(git --git-dir="$origin" for-each-ref --format='%(refname:short)' 'refs/heads/feat/update-flake-lock-*')"
grep -Fq updated "$TEST_REPO/flake.lock"
grep -Fq 'pr create --repo bhechinger/WonkoOS --base main' "$GH_LOG"
grep -Fq 'pr view https://github.com/bhechinger/WonkoOS/pull/99 --json state --jq .state' "$GH_LOG"
grep -Fq 'flake check --all-systems --no-build --no-update-lock-file' "$NIX_LOG"
test "$(git -C "$TEST_REPO" rev-parse main)" = "$(awk '/^flake check --all-systems --no-build --no-update-lock-file / { print $6 }' "$NIX_LOG")"

new_repo nochange
run_update nochange
test "$(git -C "$TEST_REPO" branch --show-current)" = main
test -z "$(git -C "$TEST_REPO" for-each-ref --format='%(refname:short)' 'refs/heads/feat/update-flake-lock-*')"

new_repo dirty
printf '%s\n' dirty >>"$TEST_REPO/flake.lock"
if run_update change >/dev/null 2>&1; then
	printf 'update script accepted a dirty worktree\n' >&2
	exit 1
fi
test "$(git -C "$TEST_REPO" branch --show-current)" = main

new_repo wrong-branch
git -C "$TEST_REPO" switch -q -c work
if run_update change >/dev/null 2>&1; then
	printf 'update script accepted a non-main branch\n' >&2
	exit 1
fi
test "$(git -C "$TEST_REPO" branch --show-current)" = work

new_repo extra
: >"$GH_LOG"
if run_update extra >/dev/null 2>&1; then
	printf 'update script accepted an extra changed file\n' >&2
	exit 1
fi
case "$(git -C "$TEST_REPO" branch --show-current)" in
feat/update-flake-lock-*) ;;
*) exit 1 ;;
esac
test ! -s "$GH_LOG"

new_repo check-fail
: >"$GH_LOG"
if run_update check-fail >/dev/null 2>&1; then
	printf 'update script ignored a failed flake check\n' >&2
	exit 1
fi
case "$(git -C "$TEST_REPO" branch --show-current)" in
feat/update-flake-lock-*) ;;
*) exit 1 ;;
esac
test ! -s "$GH_LOG"

new_repo check-rewrite
: >"$GH_LOG"
if run_update check-rewrite >/dev/null 2>&1; then
	printf 'update script accepted a lockfile rewritten during validation\n' >&2
	exit 1
fi
case "$(git -C "$TEST_REPO" branch --show-current)" in
feat/update-flake-lock-*) ;;
*) exit 1 ;;
esac
test ! -s "$GH_LOG"
test -z "$(git --git-dir="$origin" for-each-ref --format='%(refname:short)' 'refs/heads/feat/update-flake-lock-*')"

new_repo hook
hook_dir=$test_root/hooks
mkdir "$hook_dir"
cat >"$hook_dir/pre-commit" <<'EOF'
#!/bin/sh
printf '%s\n' injected >injected-file
git add injected-file
EOF
chmod +x "$hook_dir/pre-commit"
git -C "$TEST_REPO" config core.hooksPath "$hook_dir"
: >"$GH_LOG"
if run_update change >/dev/null 2>&1; then
	printf 'update script accepted a file injected by a commit hook\n' >&2
	exit 1
fi
case "$(git -C "$TEST_REPO" branch --show-current)" in
feat/update-flake-lock-*) ;;
*) exit 1 ;;
esac
test ! -s "$GH_LOG"
test -z "$(git --git-dir="$origin" for-each-ref --format='%(refname:short)' 'refs/heads/feat/update-flake-lock-*')"

new_repo post-commit-hook
hook_dir=$test_root/post-commit-hooks
mkdir "$hook_dir"
cat >"$hook_dir/post-commit" <<'EOF'
#!/bin/sh
printf '%s\n' unexpected >injected-file
git add injected-file
git commit --no-verify -q -m injected
printf '%s\n' hidden-update >flake.lock
git add flake.lock
git commit --no-verify -q -m hide-injection
EOF
chmod +x "$hook_dir/post-commit"
git -C "$TEST_REPO" config core.hooksPath "$hook_dir"
: >"$GH_LOG"
if run_update change >/dev/null 2>&1; then
	printf 'update script accepted a commit chain injected by a post-commit hook\n' >&2
	exit 1
fi
case "$(git -C "$TEST_REPO" branch --show-current)" in
feat/update-flake-lock-*) ;;
*) exit 1 ;;
esac
test ! -s "$GH_LOG"
test -z "$(git --git-dir="$origin" for-each-ref --format='%(refname:short)' 'refs/heads/feat/update-flake-lock-*')"

new_repo lock-hook
hook_dir=$test_root/lock-hooks
mkdir "$hook_dir"
cat >"$hook_dir/pre-commit" <<'EOF'
#!/bin/sh
printf '%s\n' hook-updated >flake.lock
git add flake.lock
EOF
chmod +x "$hook_dir/pre-commit"
git -C "$TEST_REPO" config core.hooksPath "$hook_dir"
: >"$GH_LOG"
: >"$NIX_LOG"
run_update change
test "$(git -C "$TEST_REPO" show main:flake.lock)" = hook-updated
test "$(git -C "$TEST_REPO" rev-parse main)" = "$(awk '/^flake check --all-systems --no-build --no-update-lock-file / { print $6 }' "$NIX_LOG")"

new_repo base-move
base=$(git -C "$TEST_REPO" rev-parse main)
hook_dir=$test_root/base-move-hooks
mkdir "$hook_dir"
cat >"$hook_dir/pre-push" <<'EOF'
#!/bin/sh
while read -r _ _ remote_ref _; do
	if [ "$remote_ref" = refs/heads/main ]; then
		base=$(git rev-parse main)
		tree=$(git rev-parse 'main^{tree}')
		moved=$(printf '%s\n' 'advance main' | git commit-tree "$tree" -p "$base")
		git push --no-verify -q origin "$moved:refs/heads/main"
	fi
done
EOF
chmod +x "$hook_dir/pre-push"
git -C "$TEST_REPO" config core.hooksPath "$hook_dir"
: >"$GH_LOG"
if run_update change >/dev/null 2>&1; then
	printf 'update script merged onto an unvalidated base\n' >&2
	exit 1
fi
case "$(git -C "$TEST_REPO" branch --show-current)" in
feat/update-flake-lock-*) ;;
*) exit 1 ;;
esac
test "$base" != "$(git --git-dir="$origin" rev-parse refs/heads/main)"
base_move_branch=$(git -C "$TEST_REPO" branch --show-current)
test "$(git -C "$TEST_REPO" rev-parse HEAD)" = "$(git --git-dir="$origin" rev-parse "refs/heads/$base_move_branch")"

new_repo head-move
hook_dir=$test_root/head-move-hooks
mkdir "$hook_dir"
cat >"$hook_dir/pre-push" <<'EOF'
#!/bin/sh
while read -r _ _ remote_ref _; do
	if [ "$remote_ref" = refs/heads/main ]; then
		branch=$(git branch --show-current)
		head=$(git rev-parse HEAD)
		tree=$(git rev-parse 'HEAD^{tree}')
		moved=$(printf '%s\n' 'advance PR head' | git commit-tree "$tree" -p "$head")
		git push --no-verify -q origin "$moved:refs/heads/$branch"
	fi
done
EOF
chmod +x "$hook_dir/pre-push"
git -C "$TEST_REPO" config core.hooksPath "$hook_dir"
: >"$GH_LOG"
: >"$NIX_LOG"
if run_update change >/dev/null 2>&1; then
	printf 'update script reported an unrecognized PR merge\n' >&2
	exit 1
fi
case "$(git -C "$TEST_REPO" branch --show-current)" in
feat/update-flake-lock-*) ;;
*) exit 1 ;;
esac
validated_head=$(awk '/^flake check --all-systems --no-build --no-update-lock-file / { print $6 }' "$NIX_LOG")
head_move_branch=$(git -C "$TEST_REPO" branch --show-current)
test "$(git --git-dir="$origin" rev-parse refs/heads/main)" = "$validated_head"
test "$(git --git-dir="$origin" rev-parse "refs/heads/$head_move_branch^")" = "$validated_head"
grep -Fq 'pr view https://github.com/bhechinger/WonkoOS/pull/99 --json state --jq .state' "$GH_LOG"
