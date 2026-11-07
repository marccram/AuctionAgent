# AuctionAgent: WoW Forever Addon Spec

Build target: Claude Code. Read this whole file, then follow "Build Order" at the bottom.

## 1. Summary

AuctionAgent helps a player decide what to auction and what to vendor, with minimal friction.

1. **At the Auction House:** when the bags are open on the Sell tab, show a panel listing every sellable bag item with its current AH price, vendor price, and a suggested listing price.
2. **While questing:** item tooltips show the current AH value. Items whose AH value beats vendor value by a user-defined margin (default > 50%) trigger a subtle, non-disruptive alert.
3. **Marking:** the player can mark items "Auction" or "Vendor" while questing. At the Auction House or a vendor, marked items are queued or sold automatically (with confirmation).

## 2. Target Client and Assumptions (verify first)

- **WoW Forever runs on the Midnight Retail client**, not a Classic client. TOC `## Interface: 16001` (confirm against the installed client; it changes with betas). Classic-era addons and libraries will not load.
- Expect the **modern `C_AuctionHouse` API**, not the legacy `QueryAuctionItems` / `GetAuctionItemInfo` API.
- Expect Midnight-era **"secret values" restrictions** on some API returns. Wrap numeric reads defensively (pcall plus type checks) and never do arithmetic on a value without verifying it is a plain number. Other Forever addons (e.g. VendorPricePlus) have needed this treatment.
- Item info can be asynchronous. Use `Item:CreateFromItemID` / `ContinueOnItemLoad` or `GET_ITEM_INFO_RECEIVED`.
- Because the API surface is moving, **Step 0 of the build is an API probe**: write a tiny debug addon or `/aa debug` command that logs which of the functions below exist and what they return in the live client. Do not assume.
- Check how existing Forever addons coexist: Auctionator ("Forever Auctionator") and VendorPricePlus both add tooltip lines. AuctionAgent must not duplicate their price rows (see 6.3).

Functions to probe: `C_AuctionHouse.SendBrowseQuery`, `SendSearchQuery`, `ReplicateItems` / `GetReplicateItemInfo` (if present), `GetCommoditySearchResultInfo`, `GetItemSearchResultInfo`, `PostItem`, `PostCommodity`, `GetItemCommodityStatus`, `GetItemKeyInfo`, `GetBagItemInfo`-style bag APIs (`C_Container.*`), `C_Item.GetItemInfo`, `C_Container.UseContainerItem`, `AuctionHouseFrame` and its tab system, `MerchantFrame`, `TooltipDataProcessor.AddTooltipPostCall`, `C_Item.GetItemSellPrice` or `select(11, GetItemInfo())`.

## 3. Core Concepts

### 3.1 Price model
For each item, store:
- `vendor` (copper, per unit)
- `marketValue` (copper, per unit): derived from the latest AH scan data
- `lastSeen` (timestamp), `numAuctions`, `quantity`
- `source` ("scan", "search", "none")

**Market value** = low-outlier-resistant estimate. Default: take the lowest ~15% of listings by price (min 1, max ~10 listings) and compute the median. Fall back to the lowest buyout if fewer than 3 listings. Keep the algorithm in one module so it can be swapped.

### 3.2 Profit
- `ahNet = marketValue * (1 - AH_CUT)` where `AH_CUT = 0.05` (make a constant; verify with the live client, since deposit rules also apply).
- `margin = (ahNet - vendor) / vendor`. If `vendor == 0`, treat any AH value > 0 as "unbounded" margin and flag it as high.
- **High-margin item** = `margin >= threshold` (default 0.50) AND `ahNet - vendor >= minProfitCopper` (default 10 silver; prevents flagging a 2c item worth 5c). Both user-configurable.

### 3.3 Suggested sell price
- Default strategy: **undercut** the current lowest buyout by a configurable amount (default 1 copper or 1%, whichever is larger, user choice in settings), never below `max(vendor * 1.05, minimumListingPrice)`.
- If no AH data is available: suggest nothing; show "No data" and offer a one-click scan.
- Strategy options in settings: Undercut lowest, Match market value, Percent of market (e.g. 95%).
- Duration default 24h (setting; deposit cost shown when API provides it).
- Commodities (stackable) are priced per unit; non-commodities per item. Respect the modern split.

## 4. Data Acquisition

AH data is only readable while the AH is open. Design for that:

1. **On AH open:** offer (and optionally auto-run per setting) a scan.
   - Preferred: a full or bulk scan if the API exposes one and is not heavily throttled (probe `ReplicateItems`).
   - Fallback: targeted queries only for items currently in the player's bags (and marked items). This is the primary path if full scans are unavailable or throttled.
2. **Throttle awareness:** respect `AUCTION_HOUSE_THROTTLED_*` events and the "ready" state. Queue queries and run them as the system becomes available. Show progress ("Scanning 7/23").
3. **Persistence:** save prices in SavedVariables (`AuctionAgentDB`) keyed by `realm-faction`/connected-realm and `itemID` (for gear also `itemLevel`/bonus-aware key if the API requires an item key). Store timestamps. Prune entries older than a configurable age (default 14 days).
4. **Staleness:** UI and tooltips show age ("2h ago"). Dim prices older than 24h. Never hide stale data, just label it.
5. **Optional interop (stretch):** if Auctionator is loaded, read its price API as a fallback source. If a documented API isn't present, do nothing. Don't depend on it.

## 5. Features

### 5.1 Sell Panel (at the Auction House)
Trigger: AH open, Sell tab active, bags open.

- A panel docked to the AH frame lists all **sellable** bag items (exclude soulbound, quest items, and items the AH rejects; use bag item info for bound status and `C_AuctionHouse` eligibility checks).
- Columns: Icon + name (quality-colored), Qty, Vendor (each), Market (each), Suggested price, Est. profit vs vendor, Margin %, Data age, Action.
- Sort by est. total profit descending by default. Click headers to sort. Filter box and toggles: "High margin only", "Marked only".
- Row actions: **Post** (posts at suggested price with default duration), **Vendor-mark**, **Ignore** (never show again; manage in settings).
- Header buttons: **Scan**, **Post all marked**, **Post all high-margin** (confirmation dialog summarizing count, total listing value, total deposit).
- Posting uses the Blizzard flow (`PostItem` / `PostCommodity`). These calls may be protected or require a hardware event. Each post must be triggered by a click; "Post all" should walk the queue one click at a time or, if the client allows, batch within allowed constraints. Probe this early. If batch posting is blocked, implement a "Post next" button that advances the queue.
- Stack handling: let the user choose per-row stack size and number of stacks (default: post whole stack as one listing for commodities; configurable).

### 5.2 Tooltips
- Add a line for AH market value (per unit, and x stack if applicable) to item tooltips using `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ...)`.
- Also show: age of data, margin %, and a "Worth auctioning" or "Vendor it" hint based on the thresholds.
- **Coexistence:** if Forever Auctionator or VendorPricePlus is active, show only the lines they lack (margin / recommendation), configurable ("Compact mode"). Detect by `C_AddOns.IsAddOnLoaded`.
- Wrap all price math in defensive checks (secret values, nil item info). Never error in a tooltip hook. Fail silent.

### 5.3 Subtle Alerts (questing-friendly)
When an item is picked up (`BAG_UPDATE_DELAYED` diff, or `CHAT_MSG_LOOT` / `ITEM_PUSH` parsing) and meets the high-margin rule:

Alert channels (each independently toggleable; defaults on for the first two):
1. **Minimap button** turns red/gold (glow or color swap) with a small count badge. Tooltip on hover lists the flagged items. Resets when the player views the list, visits the AH, or marks/ignores the items.
2. **Bag slot border** (a colored border/overlay on the item icon in default bags, and Bagnon/AdiBags/ElvUI if easy). Implementation: hook the container frame item update; a thin 2px gold border. Make this module optional so a bag-addon incompatibility cannot break the core.
3. **Optional (off by default):** a quiet chat line "[AuctionAgent] Item Name: ~Xg AH vs Yg vendor (+Z%)" and/or a short sound.

Rules:
- No popups, no focus-stealing, no animation louder than a slow pulse (pulse optional, off by default).
- No alerts in combat (queue; resolve on `PLAYER_REGEN_ENABLED`).
- De-duplicate: one alert per item stack per session unless the price changes by more than a set delta.
- Alerts rely on cached prices, so with no data nothing is flagged. Show "No AH data yet" only in tooltips.

### 5.4 Marking (Auction / Vendor)
- Mark via: modifier-click on item (default Alt+Right-click; configurable, avoid conflicts), or a small tooltip hint, or slash command `/aa mark auction|vendor [itemlink]`.
- Visual: small corner icon on the item (gold coin = auction, grey bag/coin = vendor), same optional bag-integration module as 5.3.
- Persist marks by item identity (itemID for non-unique items; for gear, GUID is session-only, so persist by itemID plus link signature and re-resolve on login). Marks clear when the item leaves the bags, unless "Remember for itemID" is set.
- **At a vendor** (`MERCHANT_SHOW`): if marked-for-vendor items exist, show a small bar on the merchant frame: "Sell N marked items (value Xg)  [Sell]". One click sells all (`C_Container.UseContainerItem`). Option "auto-sell without asking" (default off). Never sell items not marked unless a separate "auto-sell grays" option is on.
- **At the AH:** marked-for-auction items are highlighted at the top of the Sell Panel with a "Post all marked" button.
- Safety: never vendor or post an item that is equipped, soulbound-to-quest, or has a high-value tag (user setting: don't auto-vendor anything above quality X or above vendor value Y).
- Include an **Undo/Buyback** note: after vendoring, print a summary and remind the player of buyback.

### 5.5 Settings
Use the Midnight Settings API (`Settings.RegisterCanvasLayoutCategory` / vertical layout; probe the current form). Slash `/aa` or `/auctionagent` opens it.

Settings:
- Margin threshold % (default 50), min profit copper (default 10s)
- Alert channels and styles, no-combat rule
- Suggested price strategy, undercut amount, floor, duration
- Auto-scan on AH open; scan scope; data max age
- Tooltip mode (full / compact / off)
- Modifier key for marking
- Ignore list management
- Coexistence toggles (hide duplicate lines)
- Debug logging

## 6. Architecture

### 6.1 File layout
```
AuctionAgent/
  AuctionAgent.toc
  Core.lua          -- addon table, events, init, SavedVariables, slash commands
  Compat.lua        -- client/API shims, secret-value-safe helpers, feature probes
  Prices.lua        -- price DB, market value algorithm, profit math, staleness
  Scanner.lua       -- AH queries, throttle queue, scan progress
  Bags.lua          -- bag enumeration, sellable filter, loot-diff detection
  Marks.lua         -- marking state, persistence, modifier-click handling
  Tooltip.lua       -- tooltip hooks, coexistence logic
  Alerts.lua        -- minimap button, bag borders, chat/sound
  UI_SellPanel.lua  -- AH Sell panel
  UI_Merchant.lua   -- vendor bar
  Settings.lua      -- options panel
  Locales/enUS.lua
  Media/            -- icons, border textures
  README.md
```
Use a plain global addon table `AuctionAgent` with sub-modules. Avoid heavy libraries; LibStub/LibDataBroker/LibDBIcon are acceptable for the minimap button if they load on the Forever client. Otherwise write a minimal custom button.

### 6.2 Data structures
```lua
AuctionAgentDB = {
  settings = { ... },
  prices = { ["realmKey"] = { [itemID] = { market=, low=, count=, qty=, t= } } },
  marks = { [itemID] = "auction" | "vendor" },   -- persistent marks
  ignore = { [itemID] = true },
}
AuctionAgentCharDB = { sessionMarks = { ... } }  -- per-character if needed
```

### 6.3 Compatibility rules
- Do not modify or taint protected Blizzard functions. Hook with `hooksecurefunc` only.
- All tooltip, bag, and AH UI code must be nil-safe and error-isolated (`pcall`) so a client patch breaks one feature, not the addon.
- If another addon already displays AH price, expose a setting to turn off ours.
- Taint check: after building, open the AH, bags, and a vendor; confirm no "action blocked" messages.

## 7. Edge Cases
- Item info not yet cached: show "..." and refresh on `GET_ITEM_INFO_RECEIVED`.
- No listings for an item: show "No listings"; suggested price blank; do not flag as high margin.
- Vendor price 0 (no-sell items): exclude from vendor math; can still be auctioned.
- Gear with varying item level/bonuses: price by the item key the AH uses; label if only a base-item price is known.
- Pets/mounts/recipes: handle via item keys; if unsupported by the probe, skip with a note.
- Stacks vs commodities: never mix per-unit and per-stack numbers. Always label.
- Multiple characters/realms: DB is keyed per connected realm group + faction (or neutral AH).
- Login with bags unloaded: delay bag scans until `BAG_UPDATE_DELAYED`.
- Reload during scan: persist partial results safely.

## 8. Non-Goals (v1)
- No auto-buying or sniping.
- No cancel/relist (post-expiry management) in v1; list it as v2.
- No external price sources (TSM / web) in v1.
- No selling of soulbound items.

## 9. Acceptance Criteria
1. Loads on the WoW Forever client with no Lua errors (`/console scriptErrors 1`, BugSack).
2. Open AH, Sell tab, bags: panel lists all sellable items with vendor price, market price (after scan), suggested price, profit, margin.
3. Scan completes without hitting throttle errors; progress shown; results persisted across `/reload`.
4. Tooltip shows AH value and margin on bag items, quest rewards, and loot. No duplicate lines when Auctionator/VendorPricePlus are active.
5. Picking up an item with margin ≥ threshold turns the minimap icon red and/or borders the bag item; nothing appears in combat; no popups.
6. Marking an item shows an indicator; at a vendor, one click sells exactly the vendor-marked items; at the AH, marked items are queued for posting.
7. Changing the threshold in settings changes which items are flagged immediately.
8. No taint/"action blocked" errors during AH, bag, or vendor use.

## 10. Build Order for Claude Code

0. **Probe** (`Compat.lua` + `/aa debug`): confirm Interface number, which `C_AuctionHouse` and `C_Container` functions exist, how bag item info and sell price are read, whether secret values appear, whether batch posting is allowed. Write findings into `docs/PROBE-NOTES.md` and adjust this spec where reality differs.
1. Scaffold TOC, Core, SavedVariables, slash commands.
2. Prices + profit math (pure Lua, unit-testable outside the game with a small busted/plain-Lua test harness).
3. Bags enumeration + sellable filter + loot detection.
4. Tooltip module.
5. Scanner (targeted bag-item queries first; full scan if available).
6. Sell Panel UI.
7. Alerts (minimap first, bag borders second, optional chat/sound).
8. Marks + vendor bar + AH queue.
9. Settings panel.
10. Coexistence pass with Auctionator and VendorPricePlus, then taint/error pass.
11. Package: README, CHANGELOG, release zip with `-forever` naming per CurseForge convention.

Testing notes: pure logic (market value, margin, undercut, filtering) should have plain-Lua tests. UI and API behavior must be verified in-game; keep a manual test checklist in `TESTING.md` mirroring Section 9.

## 11. Open Questions to Resolve in Step 0
- Does the Forever AH expose a bulk/replicate scan, and what are its throttle limits?
- Can `PostItem` / `PostCommodity` be called repeatedly from one click, or one post per click?
- Is `C_Container.UseContainerItem` at a merchant still unrestricted for batch selling?
- Which bag addons are common on Forever (for border integration)? Start with default bags.
- Exact AH cut and deposit formula on Forever.
