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

Releases are made entirely in the GitHub UI; nothing is run locally. On the repository's
Releases page, draft a new release and type a new tag, such as `v0.7.1`, targeting `main`.
Click "Generate release notes", edit the result into notes for players (what changed for
them, not how the code changed) and publish.

Publishing starts the [release workflow](.github/workflows/release.yml). It writes the
release's text to CHANGELOG.md, packages the tagged commit with [.pkgmeta](.pkgmeta) and
uploads one file to CurseForge, whose changelog is exactly that text. A release with no
text uploads nothing. Pushing a tag by itself releases nothing, and neither does a push to
`main`. The tag name becomes the addon version. A tag containing `alpha` or `beta`, such
as `v0.7.1-beta1`, is published as that file type; any other tag is a release.

The generated notes list the pull requests merged since the last release by title, leaving
out Dependabot's (see [.github/release.yml](.github/release.yml)). Good pull request
titles therefore make good release notes, and less editing.
`make package-check` lists the files a package would contain.

## Pull requests

Open pull requests into `main`, one topic per pull request. Fill in the template's
summary and how you tested it. Title it for players, since titles become the release
notes, as [Releasing](#releasing) describes.
