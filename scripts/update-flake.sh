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
if [ -n "$(git status --porcelain)" ] || [ "$(git diff-tree --no-commit-id --name-only -r HEAD)" != flake.lock ]; then
	printf 'The update commit contains or left changes beyond flake.lock; leaving %s for inspection.\n' "$branch" >&2
	exit 1
fi
nix flake check --all-systems --no-build
head=$(git rev-parse HEAD)
git push --set-upstream origin "$branch"
pr_url=$(gh pr create --repo "$repository" --base main --head "$branch" \
	--title 'flake: update inputs' \
	--body 'Automated flake input update. Validation: nix flake check --all-systems --no-build.')
current_base=$(gh pr view "$pr_url" --json baseRefOid --jq .baseRefOid)
if [ "$current_base" != "$base" ]; then
	printf 'main advanced after validation; leaving %s and %s for inspection.\n' "$branch" "$pr_url" >&2
	exit 1
fi
# ponytail: GitHub only guards the head here; require up-to-date branches if this race matters.
gh pr merge "$pr_url" --squash --delete-branch --match-head-commit "$head"
git switch main
git pull --ff-only origin main
printf 'Merged %s\n' "$pr_url"
