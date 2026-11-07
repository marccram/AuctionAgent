# Manual test checklist

Pure logic is covered by `luajit tests/run.lua`. Everything below needs the game. Turn on error display first: `/console scriptErrors 1` (or use BugSack).

## 1. Load

- [ ] Log in: no Lua errors, a one-line loaded message appears in chat.
- [ ] First login on a fresh install shows the Quick Start window; `/aa welcome` shows it again.
- [ ] `/aa` opens the options panel; it is also listed under Game Menu > Options > AddOns.

## 2. Auction House, Sell panel, scanning

- [ ] First AH visit offers a full scan (Scan now / Later / Don't ask again) until one completes.
- [ ] A full scan shows progress, completes, and says how many items were priced. Prices survive `/reload` (`/aa status`).
- [ ] With the AH open, `/aa scan bags` prices the bag items without a throttle error.
- [ ] On the Sell tab the Sell Panel docks beside the AH and lists all sellable items with vendor, market, suggested price, profit, margin, age.
- [ ] Sorting by clicking headers, the filter box, "High margin only" and "Marked only" work.
- [ ] Post on a cheap commodity (e.g. cloth): the Auctions tab shows the right quantity, per-unit price and duration; the deposit matches the Sell tab's estimate.
- [ ] Post on a non-commodity (e.g. gear): one item, buyout equals the suggested price.
- [ ] "Post all high-margin" and "Post all marked" show a confirmation with count, total value and total deposit; the first post goes through and Post next advances the queue.

## 3. Tooltips

- [ ] Bag items, quest rewards and loot show an "AH value" line, deposit estimate and a recommendation.
- [ ] Soulbound items show no recommendation.
- [ ] With Auctionator loaded: items Auctionator prices show only margin and recommendation; items it shows as Unknown still get the AuctionAgent AH value line. No duplicate price lines.
- [ ] Hovering an item with no data shows "No AH data yet", never an error.

## 4. Marks and the vendor

- [ ] Alt + left-click a bag item cycles AH, V, none with a badge; no item stays stuck on the cursor and nothing prints to chat.
- [ ] A soulbound item cycles V, none (never AH).
- [ ] At a vendor, "Sell marked (N)" shows the right count; hovering lists the items and total; clicking sells exactly the V items and prints a summary. Unmarked items are untouched.
- [ ] Marks are dropped when the item leaves the bags (unless "Keep marks" is on).
- [ ] At the AH, AH-marked items sit at the top of the Sell Panel.

## 5. Alerts

- [ ] Loot an item that clears the thresholds (lower them with `/aa set marginThreshold 0.05` and `/aa set minProfitCopper 1` to force it): the minimap button turns red with a count and the bag slot gets a gold border.
- [ ] Hovering the minimap button lists the items; clicking marks them seen.
- [ ] Nothing alerts during combat; flagged items appear after combat ends.
- [ ] The same item does not alert twice unless its price moves a lot.
- [ ] No popups, sounds or chat unless enabled.

## 6. Settings

- [ ] Changing the margin threshold changes which items are flagged immediately.
- [ ] Money fields accept `1g 50s`, `20s` and plain copper; percent fields are typed as percent; out of range values clamp.
- [ ] Reset to defaults asks for confirmation and keeps marks and prices.

## 7. Taint and errors

- [ ] With Auctionator (and VendorPricePlus) loaded: opening bags, the AH and a vendor, posting, selling and hovering items produce no "action blocked" popup and no Lua errors.
- [ ] The Sell Panel and Auctionator's own tabs both work.
