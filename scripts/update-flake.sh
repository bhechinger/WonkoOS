#!/bin/sh
set -eu

repository=bhechinger/WonkoOS

for command in git nix gh date; do
	command -v "$command" >/dev/null 2>&1 || {
		printf 'Required command not found: %s\n' "$command" >&2
		exit 1
	}
done

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
	printf 'Run this command from a Git checkout.\n' >&2
	exit 1
}
cd "$root"

if [ "$(git branch --show-current)" != main ]; then
	printf 'make update must start on main.\n' >&2
	exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
	printf 'make update requires a clean worktree.\n' >&2
	exit 1
fi
gh auth status --hostname github.com >/dev/null

git fetch origin
git merge --ff-only origin/main
if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
	printf 'Local main does not exactly match origin/main.\n' >&2
	exit 1
fi
base=$(git rev-parse HEAD)

branch=feat/update-flake-lock-$(date -u +%Y%m%d-%H%M%S)
git switch -c "$branch"
nix flake update

changes=$(git status --porcelain)
if [ -z "$changes" ]; then
	git switch main
	git branch -d "$branch"
	printf 'Flake inputs are already current.\n'
	exit 0
fi
if [ "$changes" != ' M flake.lock' ]; then
	printf 'nix flake update changed files other than flake.lock; leaving %s for inspection.\n' "$branch" >&2
	exit 1
fi

git add flake.lock
git commit -m 'flake: update inputs'
parents=$(git rev-parse HEAD^@)
if [ -n "$(git status --porcelain)" ] || [ "$parents" != "$base" ] || [ "$(git diff --name-only "$base" HEAD)" != flake.lock ]; then
	printf 'The update commit contains or left changes beyond flake.lock; leaving %s for inspection.\n' "$branch" >&2
	exit 1
fi
head=$(git rev-parse HEAD)
nix flake check --all-systems --no-build --no-update-lock-file
if [ "$(git rev-parse HEAD)" != "$head" ] || [ -n "$(git status --porcelain)" ]; then
	printf 'Validation changed the update commit or worktree; leaving %s for inspection.\n' "$branch" >&2
	exit 1
fi
git push --set-upstream origin "$branch"
pr_url=$(gh pr create --repo "$repository" --base main --head "$branch" \
	--title 'flake: update inputs' \
	--body 'Automated flake input update. Validation: nix flake check --all-systems --no-build --no-update-lock-file.')
git push --force-with-lease="refs/heads/main:$base" origin "$head:refs/heads/main"
if [ "$(gh pr view "$pr_url" --json state --jq .state)" != MERGED ]; then
	printf 'main now contains %s, but GitHub did not mark %s merged; leaving %s for inspection.\n' "$head" "$pr_url" "$branch" >&2
	exit 1
fi
git switch main
git pull --ff-only origin main
if ! git push origin --delete "$branch"; then
	remote_branch=$(git ls-remote --heads origin "$branch")
	[ -z "$remote_branch" ] || exit 1
fi
git branch -d "$branch"
printf 'Merged %s\n' "$pr_url"
