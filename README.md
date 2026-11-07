# AuctionAgent

A World of Warcraft addon for the **WoW Forever (Midnight retail) client** that answers one question quickly: *should I auction this, or vendor it?*

It prices your bag items from the Auction House, shows the answer in item tooltips, lists everything sellable in a panel beside the AH, and lets you mark items while you quest so a vendor visit or an AH visit takes one click.

- Item tooltips with AH value, margin, and a "Worth auctioning" or "Vendor it" hint
- A **Sell Panel** docked beside the Auction House: vendor price, market price, suggested price, profit, margin and data age for every sellable item, with one-click posting
- **Profit that accounts for the AH cut and the listing deposit**, so cheap items that would lose money on the AH are not recommended
- **Marks**: Alt + left-click a bag item to mark it for the AH or the vendor, then sell or post everything marked in one click
- **Quiet alerts** while questing: a minimap button and a thin gold bag border when a looted item is worth auctioning (never in combat, no popups)
- An options panel, a first-run welcome, and a taint-conscious design (hooks only; no Blizzard functions are replaced)

## Install

1. Download `AuctionAgent-<version>-forever.zip` from the [latest release](../../releases/latest).
2. Extract it so the `AuctionAgent` folder sits in your addons folder, for example `World of Warcraft\_retail_\Interface\AddOns\AuctionAgent` (adjust `_retail_` to match your WoW Forever install).
3. Start the game. On first login a Quick Start window explains the basics.

Requires the WoW Forever client (`## Interface: 16001`). Auctionator and VendorPricePlus are optional and supported.

## Quick start

1. **Get pricing.** Open the Auction House. The first time, AuctionAgent offers a full scan of the whole auction house, which gives every item a price in its tooltip while you quest. After that, the items in your bags are re-priced each time the AH opens.
2. **Mark your items.** Alt + left-click an item in your bags to cycle its mark: `AH` (gold) means auction it, `V` (grey) means vendor it, a third click clears it. Soulbound items can only be marked `V`.
3. **Sell.** At a vendor, press **Sell marked** in the merchant window. At the AH, open the Sell tab and use the Sell Panel's **Post all marked** or **Post all high-margin** buttons (both ask for confirmation first).
4. **Tune it.** Type `/aa` to open the options.

## How the numbers work

- **Market value** is the median of the cheapest listings (the lowest 15 percent, between 1 and 10 of them), so a single absurd listing does not move it.
- **Profit** = market value after the 5 percent AH cut, minus the vendor price, minus the deposit. **Margin** = profit divided by vendor price.
- An item is **worth auctioning** when margin is at least 50 percent *and* profit is at least 10 silver (both adjustable).
- **Deposit** is `max(1s, vendor price x quantity x 0.6 x hours / 24)` per listing. The 24 hour rate (60 percent) was measured on the live client; the 2 and 8 hour rates are assumed proportional. The deposit is refunded when the auction sells and lost when it expires, so by default the full deposit counts against profit (change "Deposit counted as a cost" to relax that).
- Prices are stored per connected realm and faction, dimmed after a day, and deleted after two weeks.

## Commands

| Command | What it does |
|---|---|
| `/aa` | Open the options panel |
| `/aa scan [bags\|cached]` | At the AH: full scan (default), bag items only, or reuse the snapshot the client already holds |
| `/aa list` | Sellable bag items with AH value, vendor price and profit |
| `/aa price <item>` | AH data for an item link or ID |
| `/aa mark auction\|vendor\|clear [item]` | Mark an item (no item: the one under your mouse) |
| `/aa marks [clear]` | List or clear all marks |
| `/aa set [key value]` | List or change any setting |
| `/aa panel` | Show or hide the Sell Panel |
| `/aa unignore [id\|all]` | List or clear ignored items |
| `/aa status` | Scanner state and data age |
| `/aa welcome` | Show the Quick Start window again |
| `/aa debug` | API probe (see `/aa debug help`), useful for bug reports |

## Working with other addons

If **Auctionator** already shows a price for an item, AuctionAgent adds only its margin and recommendation, so you do not get duplicate price lines. For items Auctionator has no price for (it keeps its own database, filled by its own scans), AuctionAgent shows its full AH value line. Turn this behavior off in the options ("Compact when Auctionator already shows a price"). VendorPricePlus works alongside without changes.

## Known limitations

- Auction House posting needs a click per post, so **Post all** posts the first item and then **Post next** advances the queue. An experimental "post a whole queue from one click" option exists; Blizzard may block it.
- A full scan downloads the whole auction house and the server limits how often it can run. If a scan reports a timeout, try again later or use `/aa scan cached`.
- Gear is priced by base item ID, since bulk scan data carries no item level or bonuses.
- Soulbound items cannot be auctioned, so they are only ever marked for the vendor.
- No cancel/relist management, no auto-buying or sniping, no external price sources.

## Development

Pure logic (price math, filtering, marks, alert rules, option parsing) is tested outside the game with plain Lua:

```
luajit tests/run.lua
```

To work on the addon in game, link the `AuctionAgent` folder into your addons folder so `/reload` picks up edits:

```powershell
New-Item -ItemType Junction -Path "<WoW>\_retail_\Interface\AddOns\AuctionAgent" -Target "<this repo>\AuctionAgent"
```

Build the release zip (`dist/AuctionAgent-<version>-forever.zip`) with:

```
python tools/package.py
```

UI and API behavior has to be verified in game; `TESTING.md` is the manual checklist. `docs/` holds the original spec (`SPEC.md`) and the notes from probing the client's API.

## License

[MIT](LICENSE)
