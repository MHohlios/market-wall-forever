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

## Credits

The disenchant outcome tables in `Disenchant.lua` are adapted from
[Disenchantry](LICENSES/Disenchantry.txt) (MIT).
