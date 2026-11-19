# MarketWall

A World of Warcraft (Forever) auction house addon. It adds a Market tab with:

- **Watchlist, Snipes and Dips** built on each item's wall price: the lowest price
  level with real supply behind it, tracked over time.
- **Bait Detect**: commodities that look baited, and one button to buy the cheap copies.
  See below.
- **Sell**: your sellable bag items as an icon grid, grouped by the best outlet for each
  (auction house, disenchant or vendor, by the same rule as mob values' Optimal), with the
  current listings or the price history beside them. The price starts at the lowest
  listing, skipping flagged bait, and warns before a post that looks like a mistake.
- **Item search**: an MW button on the minimap opens a window, anywhere in the world,
  to look up any item MarketWall has seen. See below.
- **Tooltips**: the market wall, vendor price and expected disenchant value, with the
  one that pays most after the cut marked best; the disenchant materials with their odds
  and prices; then high/low against the median and the 7-day trend. Hovering a mob shows
  its value per kill. See below.

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

## Mob values

MarketWall records each kill you, your pet or your party make and what it dropped.
Hovering a mob adds its kill count and its value per kill to the tooltip: median and
average under Vendor, Market, Skinning (when included) and Optimal, the Optimal average
without rare drops, and the top drop. Values show once a mob has **Minimum kills**.

The search window's **Mobs** switch lists every recorded mob, sorted by median per kill
under the Optimal, Market or Vendor lens, with a name filter. Click a mob for its drop
table. Settings has the mob rows: disenchanting and skinning in Optimal (Auto, Always,
Never), the rare drop threshold and the minimum kills. The Mobs view added
`MobsView.lua`, so restart the game once after updating to it.

## Farm sessions and the ledger

Right-click the **MW** button to start a labelled farm session (a recent label starts
again in one click), pause or resume it, stop it, or open the Sessions view. `/mw
session start <label>`, `stop`, `pause` and `resume` do the same. While a session is
open, a small movable tracker shows its time, value earned and gold per hour under the
Optimal, Market or Vendor lens. Logging out pauses it; paused time doesn't count.

The search window's **Sessions** view lists every session, filtered by label; with one
label picked it gives the best and median gold per hour of its runs. Click a session for
its value earned at current prices and at the moment it ended, coins looted, gaps of over
10 minutes with nothing gained, and each activity's share, value and top items.
Right-click an activity to rename it, merge it into another, or unmerge a member; groups
apply to every session.

The **Ledger** view charts your gold and lists income and spending by source for a week
or a month, for this character or all of them. Gold changes it can't attribute go to
Other, so it always matches your gold. Settings has the Salvager mode and bonus rows;
Reset to defaults keeps them, as they were imported once from Disenchantry.

These views added `LedgerView.lua`, `SessionsView.lua` and `SessionTracker.lua`, and the
recording added `Ledger.lua`, `Quests.lua` and `Sessions.lua`, so restart the game once
after updating to them.

## Bait Detect

A seller posts a unit or two far under the market so others copy that price, then buys
the copies and relists them. The newest listing at a price sells first.

An item is listed as possibly baited when its cheapest price level sits at least
`baitMinUnder` under the wall (50% by default, held to 10% to 95%), below the item's own
normal range, and has stayed at that price for two scans in a row
(full scans or live searches). Commodities only. On an item's first day its normal range
is today's wall.

Every number shows from an item's first scan. Until an item has `minHistoryDays` days of
data (5 by default, "Days before data is reliable"), tooltips, the item window, the Sell page
and the Snipes and Dips Data column flag it in orange; the setting hides nothing. Dips need at
least one earlier day to compare against.
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

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and the rules a change must keep, and
[SECURITY.md](SECURITY.md) to report a vulnerability privately.

## License and credits

MarketWall is released under the [MIT License](LICENSE). The disenchant outcome tables
in `Disenchant.lua` are adapted from Disenchantry and keep its own MIT notice in
[LICENSES/Disenchantry.txt](LICENSES/Disenchantry.txt).
