#!/bin/sh
# Release helpers. See CONTRIBUTING.md#releasing.
#
#   release.sh notes VERSION [CHANGELOG]  rename "## Unreleased" to "## VERSION (today)"
#   release.sh check VERSION [CHANGELOG]  fail unless CHANGELOG has a "## VERSION" heading
#   release.sh tag VERSION                check main is ready, then tag VERSION and push the tag
set -eu

fail() {
	echo "release: $*" >&2
	exit 1
}

usage() {
	fail "usage: release.sh notes|check|tag VERSION [CHANGELOG]"
}

has_heading() { # VERSION CHANGELOG
	awk -v heading="## $1" '
		$0 == heading || index($0, heading " ") == 1 { found = 1 }
		END { exit !found }
	' "$2"
}

check_heading() { # VERSION CHANGELOG
	has_heading "$1" "$2" || fail "$2 has no '## $1' heading"
}

notes() { # VERSION CHANGELOG
	grep -qx '## Unreleased' "$2" || fail "$2 has no '## Unreleased' section"
	awk '
		$0 == "## Unreleased" { inside = 1; next }
		inside && /^## / { exit }
		inside && NF { found = 1; exit }
		END { exit !found }
	' "$2" || fail "the Unreleased section of $2 is empty"
	! has_heading "$1" "$2" || fail "$2 already has a '## $1' heading"

	awk -v heading="## $1 ($(date +%F))" '
		!renamed && $0 == "## Unreleased" { print heading; renamed = 1; next }
		{ print }
	' "$2" > "$2.tmp"
	mv "$2.tmp" "$2"
	echo "Renamed '## Unreleased' to '## $1' in $2."
}

tag() { # VERSION
	git fetch --quiet --tags origin
	[ "$(git symbolic-ref --short -q HEAD)" = main ] || fail "HEAD is not main"
	[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] ||
		fail "main is not origin/main; pull or push first"
	[ -z "$(git status --porcelain)" ] || fail "the working tree is not clean"
	! git rev-parse -q --verify "refs/tags/$1" > /dev/null || fail "tag $1 already exists"
	check_heading "$1" CHANGELOG.md

	git tag -a "$1" -m "MarketWall $1"
	git push origin "refs/tags/$1"
}

[ $# -ge 2 ] || usage
command=$1
version=$2
changelog=${3:-CHANGELOG.md}
case $version in
v?*) ;;
*) fail "VERSION must start with v, such as v0.7.0 (got '$version')" ;;
esac

case $command in
notes) notes "$version" "$changelog" ;;
check) check_heading "$version" "$changelog" ;;
tag) tag "$version" ;;
*) usage ;;
esac
