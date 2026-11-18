# MarketWall

A World of Warcraft (Forever) auction house addon. It adds a Market tab with:

- **Watchlist, Snipes and Dips** built on each item's wall price: the lowest price
  level with real supply behind it, tracked over time.
- **Bait Detect**: commodities that look baited, and one button to buy the cheap copies.
  See below.
- **Sell**: your sellable bag items with their wall price, a 7-day chart, and posting
  at the wall price.
- **Item search**: an MW button on the minimap opens a window, anywhere in the world,
  to look up any item MarketWall has seen. See below.
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

**New files need a full client restart.** `/reload` picks up edits to files the game
already knows, but a new file in `MarketWall.toc`, or a new `Bindings.xml`, loads only
after quitting and restarting the game. The item search window added `PriceView.lua`,
`Search.lua` and `Minimap.lua`, so restart the game once after updating to it.

## Item search

Click the **MW** button on the minimap's edge to open or close the search window. Drag
the button to move it round the edge. `/mw minimap`, or **Minimap button** in Settings,
hides or shows it; `/mw search` opens the window either way.

Type part of a name to match items MarketWall has seen in a scan, or shift-click an item
link into the box. Your last 10 searches are listed under Recent. The item view has the
chart with a 7 days / 30 days / All switch, the item's numbers, and Add to watchlist.
Live listings load only while the auction house is open. The window moves by dragging,
remembers where you left it, and closes with Escape.

## Bait Detect

A seller posts a unit or two far under the market so others copy that price, then buys
the copies and relists them. The newest listing at a price sells first.

An item is listed as possibly baited when its cheapest price level sits under the wall,
below the item's own normal range, and has stayed at that price for two scans in a row
(full scans or live searches). Items need the usual days of history; commodities only.
Copies are the units posted at the bait price since it first appeared.

Click an item to search it. Set **Buy at or below** (it starts at the bait price) and
choose **Leave bait** or **Buy bait**, then press the action button. Each press does
one thing: one search, one buy, or one confirm. Presses during the game's search
throttle or the minimum gap between searches (`baitSearchGap`, at least 1 second) do
nothing. A sound plays when a search finds units to buy.

- **Leave bait** buys the copies and leaves the original bait listed. The game always
  sells the cheapest units first, so levels above the bait can only be bought with
  Buy bait; the page says how many that leaves out.
- The game quotes the final price before a purchase completes. MarketWall confirms only
  if no unit is over your price, otherwise it cancels and says why on the button. With
  Leave bait it also cancels unless every unit is at the bait price, since any other
  quote means the supply changed and the purchase could take the bait.
- By default the confirm is its own press. Untick **Bait confirm press** in Settings to
  confirm right after the quote, if the game allows that without a key press.
- Every purchase through MarketWall is logged with its time, item, units, unit price
  and total.

**Key binding:** Key Bindings > AddOns > MarketWall > "Bait Detect: search or buy" does
exactly what the button does.

Press the key yourself. Turbo keys, auto-clickers and macro software can get your
account banned. MarketWall never searches or buys on its own.

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
