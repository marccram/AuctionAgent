# AuctionAgent: Step 0 findings

Fill this in from the in-game probe, then adjust SPEC.md where reality differs.

## How to run the probe

1. `/console scriptErrors 1`
2. `/aa debug` anywhere. Copy the window contents (click, Ctrl+A, Ctrl+C) and paste them to Claude. The same text is saved to `WTF/Account/<acct>/SavedVariables/AuctionAgent.lua` (`debugLog`) after `/reload` or logout.
3. Open the Auction House, then:
   - `/aa debug` again (adds AH frame/tab info and throttle state)
   - `/aa debug query` (searches the first bag item; or `/aa debug query <itemID>`), wait ~2s, `/aa debug copy`
   - Optional: `/aa debug replicate` (bulk scan; long server cooldown, run once), wait, `/aa debug copy`
   - `/aa debug events` logs throttle and result events while you browse the AH normally
4. At a vendor: `/aa debug` once to confirm MerchantFrame.

## Findings so far (probe run 2026-11-06, build 1.60.1 / 70790)

- TOC `## Interface: 16001` loads. `WOW_PROJECT_ID` = 18. The realm string combines region, connected realm and server type, plus faction. `GetAutoCompleteRealms` returned empty.
- Present: all probed `C_AuctionHouse` functions (browse/search/replicate/post/deposit/commodity status/item key), `C_Container.*`, `C_Item.GetItemInfo`, `C_Item.IsBound`, `TooltipDataProcessor.AddTooltipPostCall`, `C_TooltipInfo.GetBagItem`, Settings canvas/vertical category APIs, secret-value helpers (`issecretvalue`, `issecrettable`, `canaccessvalue`, `hasanysecretvalues`, `C_Secrets`).
- Missing: `C_Item.GetItemSellPrice`, global `GetItemInfo`, `C_AuctionHouse.GetAuctionHouseDuration`. **Vendor price = 11th return of `C_Item.GetItemInfo`** (Copper Rod 24c, Fishing Pole 4c, Oil of Olaf 3c).
- Bag item info fields: `hasLoot, hasNoValue, hyperlink, iconFileID, isBound, isFiltered, isLocked, isReadable, itemID, itemName, quality, stackCount`. No secret values observed. Use `isBound` and `hasNoValue` for the sellable filter.
- `ContainerFrameCombinedBags` is the active bag frame (shown at vendor and AH), `ContainerFrame1` is not. Bag border/mark overlays must support the combined bags frame.
- `AuctionHouseFrame` is load-on-demand (nil until first opened). Children include `SellTab, ItemSellFrame, CommoditiesSellFrame, ItemSellList, CommoditiesSellList, AuctionsTab, BuyTab, BrowseResultsFrame`. Display modes: `Auctions, Buy, CommoditiesBuy, CommoditiesSell, ItemBuy, ItemSell, WoWTokenBuy, WoWTokenSell`. Dock the sell panel by hooking mode changes to `ItemSell`/`CommoditiesSell`.
- `IsThrottledMessageSystemReady()` returns true at idle.

### AH data shapes (probed at the AH)

- `GetItemKeyInfo(key).isCommodity` says up front which result API to use. `GetItemCommodityStatus(location)`: 1 = item, 2 = commodity.
- **Throttle:** a search round trip is ~0.1-0.2s (`MESSAGE_SENT` then `RESPONSE_RECEIVED`), and `THROTTLED_SYSTEM_READY` fires ~0.4s after the send. Budget about 0.5s per targeted query.
- **Result events fire twice** per query (second fires with owner names filled in). Process the first, ignore the repeat.
- **Commodity** (`COMMODITY_SEARCH_RESULTS_UPDATED(itemID)`): `GetNumCommoditySearchResults(itemID)` rows, `GetCommoditySearchResultsQuantity(itemID)` total units. Each row `GetCommoditySearchResultInfo(itemID, i)` has `unitPrice` (**per unit**), `quantity` (units on that listing), `auctionID`, `timeLeftSeconds`, `owners`. Rows are sorted cheapest first. Example: Oil of Olaf 13 rows / 324 units, 19c-25c.
- **Non-commodity** (`ITEM_SEARCH_RESULTS_UPDATED(itemKey)`): `GetNumItemSearchResults(itemKey)`, `GetItemSearchResultInfo(itemKey, i)` has `buyoutAmount` (per item, quantity 1), `itemLink`, `itemKey` (with `itemLevel`), `timeLeft` (enum 1-4), `owners`. Fishing Pole: 27 rows at 100c. Rows with `buyoutAmount` 0 (bid only) must be skipped.
- **Bulk scan works:** `ReplicateItems()` then `REPLICATE_ITEM_LIST_UPDATE`; `GetNumReplicateItems()` = 96,366 on this realm. `GetReplicateItemInfo(i)` is **0-based** and returns: 1 name, 2 icon, 3 count, 4 quality, 5 usable, 6 level, 7 levelType, 8 minBid, 9 minIncrement, 10 buyoutPrice (**total for the stack, divide by count**), 11 bidAmount, 12 highBidder, 13 bidderFullName, 14 owner, 15 ownerFullName, 16 saleStatus, 17 itemID, 18 hasAllInfo. No secret values. Rows carry no item level or bonuses (use `GetReplicateItemLink(i)` if needed), so gear is priced by base itemID and labeled as such. Process in chunks over several frames; 96k rows in one frame will freeze the client. Replicate cooldown is not yet measured (retail is ~15 min).
- Scan design: bulk replicate is the primary path (one call prices every item and powers tooltips for all items); targeted per-item search is the fallback and for fresh per-item accuracy before posting.

Still needed: a second replicate call to measure the cooldown, and a manual `PostItem`/`PostCommodity` and merchant batch-sell test once those features exist.

### Deposit (spec gap found in play)

The original spec's profit math ignored the listing deposit, which can exceed the whole profit on cheap items (example: a low-level enchanting wand vendors for 1s and the minimum deposit is 1s). Profit and margin now subtract an estimated deposit, weighted by `depositWeight` (1 = full, 0 = ignore). Deposit is refunded when the auction sells and lost when it expires, so 1.0 is the conservative setting.

**Verified formula** (probe run on build 1.60.1, 10 items, three durations): `deposit = max(100c, vendor * qty * 0.15 * hours / 12)` per listing, i.e. 15% / 30% / 60% of total vendor value at 12h / 24h / 48h. Items with vendor price 0 still pay the 100c minimum. The minimum is per listing, not per unit (17 bandages cost the same 100c as 1), so splitting a stack into many small listings multiplies the minimum deposit. `C_AuctionHouse.CalculateCommodityDeposit(itemID, duration, qty)` and `CalculateItemDeposit(itemLocation, duration, qty)` work with duration 1/2/3 = 12h/24h/48h; use them for exact numbers while the AH is open and the formula when it is closed. Rounding mode (floor vs round) is not distinguishable from the data so far (all samples were whole numbers).

### RESOLVED: durations are 2h / 8h / 24h (measured 2026-11-06)

Duration dropdown offers 2, 8 and 24 hours (enum 1/2/3). With a 250c-vendor item the deposit is 100c at 2h and 8h (the minimum) and 150c at 24h, so **24h = 60% of vendor value**. The earlier "12/24/48h" labels were wrong. Formula now: `max(100c, vendor * qty * 0.6 * hours / 24)`. The 2h/8h rates (assumed linear: 5% / 20%) are still unmeasured because they only showed the minimum; a vendor price of roughly 5g+ would reveal them. Default duration 24h therefore costs 4x what the old model predicted, so profit numbers drop for cheap items.

Full replicate scan worked for the user (93,217 auctions, 2,354 items priced).

(History below is superseded.)

### CORRECTION: listing durations (found from a screenshot)

Blizzard's Duration dropdown on this client shows **"8 Hours"**, so the shortest duration is probably 8h, not 12h. The deposit probe only proved that duration 3 costs 60% of vendor value; durations 1 and 2 always sat at the 100c minimum, so their rates (and labels) were never actually measured. The deposit formula is written per hour (`rate * hours / 12`, i.e. linear), which is only right if the rate really is linear in hours. Still to confirm: the exact option labels in the dropdown, and a deposit reading for an item with vendor value of about 1g or more (so durations 1 and 2 clear the 100c minimum).

## Open questions (spec section 11)

| Question | Answer |
|---|---|
| Interface number on the live client | |
| Bulk/replicate scan available, throttle limits | |
| Secret values seen on which returns | |
| Bag item info fields (isBound? hyperlink? quality?) | |
| Sell price source that works (GetItemSellPrice vs GetItemInfo[11]) | |
| PostItem/PostCommodity: one per click, or batchable | (needs a manual test, not covered by the probe) |
| UseContainerItem at merchant, batch OK | (needs a manual test) |
| AH cut and deposit formula | |
| Common bag addons on Forever | |
| Auctionator / VendorPricePlus tooltip behavior | |
