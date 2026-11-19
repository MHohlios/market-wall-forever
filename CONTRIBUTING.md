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

CurseForge builds releases from tags on `main`, using [.pkgmeta](.pkgmeta). The tag name
becomes the addon version, so tag `v0.2.0` for a release. A tag containing `alpha` or
`beta`, such as `v0.2.0-beta1`, is published as that file type. Untagged commits are not
released. `make package-check` lists the files a package would contain.

## Pull requests

Open pull requests into `main`, one topic per pull request. Fill in the template's
summary and how you tested it.
