#!/bin/sh
set -eu

host=${1:-}
repository=bhechinger/WonkoOS
cache_dir=$(mktemp -d)
trap 'rm -rf -- "$cache_dir"' EXIT HUP INT TERM

pr_for_revision() {
	revision=$1
	case "$revision" in
	"" | Unknown | unknown | legacy)
		printf '%s\n' legacy
		return
		;;
	esac

	commit=${revision%-dirty}
	dirty=
	if [ "$commit" != "$revision" ]; then
		dirty=' + dirty'
	fi
	case "$commit" in
	"" | *[!0-9a-fA-F]*)
		printf '%s%s\n' unavailable "$dirty"
		return
		;;
	esac

	cache_file=$cache_dir/$commit
	if [ ! -f "$cache_file" ]; then
		if prs=$(gh api "repos/$repository/commits/$commit/pulls" \
			--jq '[.[].number] | unique | sort | map("#" + tostring) | join(",")' 2>/dev/null); then
			if [ -z "$prs" ]; then
				prs='no PR'
			fi
		else
			prs=unavailable
		fi
		printf '%s\n' "$prs" >"$cache_file"
	fi

	prs=$(sed -n '1p' "$cache_file")
	printf '%s%s\n' "$prs" "$dirty"
}

print_row() {
	printf '%-5s %-10s %-16s %-46s %-18s %s\n' "$1" "$2" "$3" "$4" "$5" "$6"
}

list_nixos() {
	generations=$(nixos-rebuild list-generations)
	printf '%s\n' "$generations" | awk '
		NR > 1 && NF { printf "%s\t%s %s\t%s\t%s\n", $1, $2, $3, $6, $NF }
	' | while IFS="$(printf '\t')" read -r generation built revision current; do
		if [ "$current" = True ]; then
			current=yes
		else
			current=
		fi
		print_row nixos "$generation" "$built" "$revision" "$(pr_for_revision "$revision")" "$current"
	done
}

list_home_manager() {
	generations=$(home-manager generations)
	printf '%s\n' "$generations" | awk '
		NF >= 7 {
			current = ($NF == "(current)" ? "yes" : "")
			printf "%s\t%s %s\t%s\t%s\n", $5, $1, $2, $7, current
		}
	' | while IFS="$(printf '\t')" read -r generation built path current; do
		revision_file=$path/home-files/.config/wonkoos/revision
		if [ -r "$revision_file" ]; then
			revision=$(sed -n '1p' "$revision_file")
		else
			revision=legacy
		fi
		print_row home "$generation" "$built" "$revision" "$(pr_for_revision "$revision")" "$current"
	done
}

print_row TYPE GENERATION DATE REVISION PR CURRENT
case "$host" in
deepthought)
	list_nixos
	list_home_manager
	;;
bob)
	list_nixos
	;;
wintermute)
	list_home_manager
	;;
*)
	printf 'Unsupported host %s; expected deepthought, bob, or wintermute.\n' "$host" >&2
	exit 1
	;;
esac
