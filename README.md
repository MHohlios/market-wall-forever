# MarketWall

A World of Warcraft (Forever) auction house addon. It adds a Market tab with:

- **Watchlist, Snipes and Dips** built on each item's wall price: the lowest price
  level with real supply behind it, tracked over time.
- **Sell**: your sellable bag items with their wall price, a 7-day chart, and posting
  at the wall price.
- **Tooltips**: market wall, normal range, high/low against the median, vendor price
  and expected disenchant value.

It needs no other auction addon.

## Install

Link this repo into the game's AddOns folder so edits here load in game:

```sh
ln -s "$PWD" "/Applications/World of Warcraft/_forever_/Interface/AddOns/MarketWall"
```

Saved data lives in `WTF/Account/<account>/SavedVariables/MarketWall.lua` and is
not tracked here.

## Development

The checks run outside the game. Nix provides Lua 5.1 (the game's version), luacheck
and busted:

```sh
nix develop --command make check
```

With direnv, `direnv allow` once and then run `make check` directly. `make lint` and
`make test` run each half alone.

- `.luacheckrc` lists the WoW globals the addon uses; add new ones there.
- `spec/` holds the busted tests. `spec/helpers/addon.lua` stubs just enough WoW API to
  load every file in `MarketWall.toc`, in order, and returns the addon's namespace.
- The tests cover logic only. The in-game check is still the real test for each change.

## Credits

The disenchant outcome tables in `Disenchant.lua` are adapted from
[Disenchantry](LICENSES/Disenchantry.txt) (MIT).
