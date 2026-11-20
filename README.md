# MarketWall

A World of Warcraft (Forever) auction house addon. It adds a Market tab with:

- **Watchlist, Snipes and Dips** built on each item's wall price: the lowest price
  level with real supply behind it, tracked over time.
- **Bait Detect**: commodities that look baited, and one button to buy the cheap copies.
  See below.
- **Sell**: your sellable bag items as an icon grid, grouped by the best outlet for each
  (auction house, disenchant or vendor, by the same rule as mob values' Optimal, except that
  Optimal can also value a container at what it opens into), always in the order auction
  house, vendor, disenchant, no reliable price (the first two show even when empty), with the current listings or
  the price history beside them. The price starts at the lowest
  listing, skipping flagged bait. The page answers what the auction house pays after the
  cut and deposit, against a vendor, and notes anything that looks like a mistake above the
  bags. It asks Yes or No before a post only when the price is far under the low end of the
  item's normal range (more than 30% under up to 1g, sliding toward 70% under for dearer
  items, as Auctionator does) or matches a bait price.
- **Item search**: an MW button on the minimap opens a window, anywhere in the world,
  to look up any item MarketWall has seen. See below.
- **Tooltips**: what one unit nets through a vendor, the market and disenchanting, after
  the auction house cut and deposit, with the one that pays most marked best; the
  disenchant materials with their odds and prices; for ore and cloth, what one unit nets
  smelted into bars or woven into bolts and sold (Dark Iron takes 8 ore a bar, cloth 2 to 5
  a bolt); a stack's worth at the best of these; then high/low against the median and the
  7-day trend. Hovering a mob shows its value per kill. See below.

Every recommendation, from the tooltip's best outlet to the Sell page's groups, mob values
and farm sessions, counts the cut and a one-unit deposit at your Sell page duration. Away
from the auction house the deposit is estimated from the vendor price, at the rate the
game's own deposits on the Sell page last showed (15% per 12 hours until then).

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
`Search.lua` and `Minimap.lua`, so restart the game once after updating to it. The
crafting data added `Crafting.lua`, `Recipes/Tailoring.lua` and `Professions.lua`, so restart
once more after updating to it.

## Item search

Click the **MW** button on the minimap's edge to open or close the search window. Drag
the button to move it round the edge. `/mw minimap`, or **Minimap button** in Settings,
hides or shows it; `/mw search` opens the window either way.

Type part of a name to match items MarketWall has seen in a scan, or shift-click an item
link into the box. Your last 10 searches are listed under Recent. The item view has the
chart with a 7 days / 30 days / All switch, the item's numbers, and Add to watchlist.
Live listings load only while the auction house is open. The window moves by dragging,
remembers where you left it, and closes with Escape.

## Crafting at the trainer and on patterns

A pattern's tooltip adds a Crafting block: the recipe it teaches and its skill, profit per
craft, the product's market (Deep, Steady, Thin or No data, with the units listed), how many
crafts pay back the pattern at its wall (or its vendor price when it isn't listed), and
whether this character knows the recipe. Known recipes come from your profession window, so
open it once per character. Tailoring patterns only for now.

At a profession trainer, each recipe row shows its training cost, profit per craft and
payback, and hovering a row adds the mats, sale value, profit, market and payback to the
tooltip. MarketWall remembers each recipe's training cost, so the payback of trainer recipes
fills in elsewhere after one visit. It never trains anything. This added `Trainer.lua`, so
restart the game once after updating to it.

## Mob values

MarketWall records each kill you, your pet or your party make and what it dropped.
Hovering a mob adds three lines to the tooltip: its worth per kill under Optimal (the
median); a grey line with the Average and the kill count; and the top drop. The Vendor and
Market comparison lives in the Mobs view's switch. Values show from the first looted kill.
Under **Kills before reliable** (a Mob values setting), the kill count turns orange and
reads "3 kills, rough", and the Mobs view keeps the kill count a plain number and adds an
orange "· N kills" after the mob's name.

A container a mob drops, such as a clam, counts in Optimal at what it opens into on
average, once you have opened some, when that beats selling it unopened. Hovering such a
container shows "Opens to" with that average and how many you opened. Farm sessions keep
counting a container at its sell value, since they count its contents when you open it.

The search window's **Mobs** view lists every recorded mob, sorted by its median value per
kill under the Optimal, Market or Vendor lens, with its average and top drop, and a name
filter. Hover a Per kill value for the average without rare drops. Click a mob for its drop
table. Settings has a Mob values group: disenchanting and skinning in Optimal (Auto, On,
Off), the rare drop threshold and the kills before values are reliable. The Mobs view added
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

Right-click a session, or click the "..." at the end of its row, to change its label,
merge it into a neighbouring session or another with its label, set its running time (for
a session left running by mistake) or delete it. Merging adds the two sessions' times and
loot under the target's label, from the earlier start. Delete asks first. Neither touches
the Ledger or Mobs, which keep their own records. While a session is open, its menu offers
Pause or Resume and Stop instead. "Rename a label..." in the label dropdown renames every
session with that label, so two labels for the same farm become one.

The **Ledger** view sums up income, spending and net for a week or a month, for this
character or all of them, shows each day's net gold as a bar, and lists income and
spending by source. Gold changes it can't attribute go to Other, and gold that changed
while MarketWall wasn't running to Unrecorded, so it always matches your gold. Settings
has the Salvager and Salvager bonus rows under Disenchant; Reset to defaults keeps them, as
they were imported once from Disenchantry.

These views added `LedgerView.lua`, `SessionsView.lua` and `SessionTracker.lua`, and the
recording added `Ledger.lua`, `Quests.lua` and `Sessions.lua`, so restart the game once
after updating to them.

## Crafting guide

The **Crafting** tab in the search window and on the Market tab lists
a profession's recipes at your saved wall prices, most profit per craft first. Pick the
profession, then **Known** (your recipes), **Learnable** (recipes you don't know yet, from a
bundled Classic table) or **All**. Hide thin markets, hide losses, or filter by name; click a
column title to sort by it.

Each row has the skill it needs in its skill-up colour at your skill (red when above it), the
mats cost (vendor-sold reagents at the vendor's price, the rest at their wall), what a craft
sells for after the cut and deposit through its best outlet (DE when disenchanting pays most),
the profit and margin, and the market: Deep, Steady or Thin by the units listed in your scans,
since the auction house reports no sales. Learnable adds where the recipe is learned, the
pattern's cost and the crafts it takes to pay for it. Money cells are compact, with the exact
amount on hover. A value MarketWall has no price for shows "no data", never 0. Clicking a recipe shows its breakdown: each reagent with its price,
source and the count in your bags; the product's vendor, market and disenchant values with
the best marked; and its listings, days seen in the last week and its 7-day trend.

Open your profession window once on each character so MarketWall can read its recipes; it
reads them again whenever the window updates. On the Market tab, clicking a learnable recipe
taught by a pattern opens the pattern's item page, which loads its live listings. Buying
it is your own press, as everywhere else. The guide added `CraftingView.lua`, so restart the
game once after updating to it.

## Bait Detect

A seller posts a unit or two far under the market so others copy that price, then buys
the copies and relists them. The newest listing at a price sells first.

An item is listed as soon as a scan finds its cheapest price level at least
`baitMinUnder` under the wall (50% by default, held to 10% to 95%) and below the item's own
normal range. Commodities only. On an item's first day its normal range is today's wall.
Until a second scan (a full scan or a live search) sees the same price again, its row is
dimmed and reads "seen once"; click it to search it live and confirm it. Once confirmed it
counts as possibly baited. Only confirmed bait can be bought against; the Sell page warns
and asks before posting at a bait price either way. Each full scan drops every record it did not refresh.

Every number shows from an item's first scan. Until an item has `minHistoryDays` days of
data (5 by default, "Days before data is reliable"), tooltips, the item window and the Sell page
flag it in orange; the setting hides nothing. In the Watchlist, Snipes, Dips and Bait Detect
lists, a low-data item's name ends with an orange " · N d", and hovering the Watchlist's Normal
range or Bait Detect's Wall cells shows the item's days of data.
The setting is held to 1 through 15, the most days of data an item can have. Dips need at least one earlier day to compare against.
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
- By default the confirm is its own press. Untick **Confirm each purchase** under Bait Detect in
  Settings to confirm right after the quote, if the game allows that without a key press.
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

## Releasing

Releases are made in the GitHub UI. Draft a new release with a new tag on `main`, generate
the release notes, edit them for players and publish. The release workflow then builds the
addon and uploads it to CurseForge, which shows the release's text as the file's changelog.
A tag containing `alpha` or `beta` is published as that file type.
[CONTRIBUTING.md](CONTRIBUTING.md#releasing) has the details, including the one-time
CurseForge token setup and how to test a beta in the CurseForge app before a wide release.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and the rules a change must keep, and
[SECURITY.md](SECURITY.md) to report a vulnerability privately.

## License and credits

MarketWall is released under the [MIT License](LICENSE). The disenchant outcome tables
in `Disenchant.lua` are adapted from Disenchantry and keep its own MIT notice in
[LICENSES/Disenchantry.txt](LICENSES/Disenchantry.txt).
