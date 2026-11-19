# Contributing to MarketWall

Thanks for helping. This page covers setup, testing and the rules every change must keep.

## Setup

Nix provides Lua 5.1 (the game's version), luacheck and busted. Run the checks with:

```sh
nix develop --command make check
```

With direnv, run `direnv allow` once and then `make check` directly. To try a change in
game, link the repo into the AddOns folder as the [README](README.md#install) shows.

## Testing

The busted tests in `spec/` cover logic only. The in-game check is the real test. A pull
request should say what you checked in game and on which client: WoW Forever, interface
16001.

## Code style

- `make check` passes: luacheck is clean and the tests pass.
- Lua 5.1 only, as the game runs it.
- Small, readable functions with clear names.
- New WoW globals go in `.luacheckrc`.

## Rules a change must keep

- Every auction search, buy or post needs the player's own hardware press.
- Nothing is queued or automated.
- No combat log (`COMBAT_LOG_EVENT_UNFILTERED`) use.
- Nothing is sent to other players.

A change that breaks one of these will not be merged.

## Releasing

Release notes are written by hand in [CHANGELOG.md](CHANGELOG.md), one pull request at a
time. Every pull request, bug fixes included, adds a line under `## Unreleased` at the top
of the file, creating that heading if it is missing. CI fails a pull request that does not
change CHANGELOG.md; only Dependabot's pull requests are exempt. Write the line for
players: what changed for them, not how the code changed.

A release takes two steps, because `main` is protected:

1. On a branch, run `make release-notes VERSION=v0.7.0`. It renames `## Unreleased` to
   `## v0.7.0 (YYYY-MM-DD)` with today's date, and stops with an error if there is no
   Unreleased section or it is empty. Open a pull request with that change and merge it.
2. On an up-to-date `main`, run `make release VERSION=v0.7.0`. It fetches from origin and
   stops unless `main` matches `origin/main`, the working tree is clean, the tag does not
   exist yet and CHANGELOG.md has a `## v0.7.0` heading. Then it creates an annotated tag
   and pushes it.

The pushed tag starts the [release workflow](.github/workflows/release.yml), which checks
the heading again and packages the addon with [.pkgmeta](.pkgmeta) for CurseForge and a
GitHub release. Only tags are released; pushes to `main` are not. The tag name becomes
the addon version. A tag containing `alpha` or `beta`, such as `v0.7.0-beta1`, is
published as that file type; any other tag is a release. CurseForge shows the whole
CHANGELOG.md at the tagged commit as the file's changelog, newest release first.
`make package-check` lists the files a package would contain.

## Pull requests

Open pull requests into `main`, one topic per pull request. Fill in the template's
summary and how you tested it, and add a line to CHANGELOG.md under `## Unreleased`, as
[Releasing](#releasing) describes.
