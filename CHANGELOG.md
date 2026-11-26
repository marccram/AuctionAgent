# Changelog

## 1.0.2

- **Deposit formula updated to the live client** (measured after the November 2026 hotfix): 5 / 20 / 60 percent of vendor value for 2 / 8 / 24 hours, rounded down, **minimum 1c** per listing (was 1s). Cheap items are no longer written off as "vendor it" because of a deposit that no longer exists.
- **Fixed tooltip deposits on older installs.** Settings saved by 1.0.0 kept the first, wrong deposit rate (15% per 12 hours), so tooltips showed a quarter of the real deposit (Hillman's Cloak: 51c instead of 2s 5c) while the Sell Panel, which asks the server, was right. Internal price constants are now always taken from the addon, never from saved settings.
- **Scan progress bar position** is now an option (Scanning > "Scan progress bar position"): above the Auction House window (new default), over its middle, or below it as before, where it could cover other addons' tabs.
- **Real deposits.** At the Auction House, the Sell Panel now uses the deposit the server reports for each listing instead of an estimate, and learns the live rates and minimum from it. Tooltips use the learned values. This covers the November 2026 deposit changes (minimum deposit 1s to 1c) without another update.
- **No more posting at a loss.** The price floor used to be vendor x 1.05, which after the 5% AH cut and the deposit earned *less* than vendoring. It now covers the cut and the deposit, then adds the 5% margin.
- **No posting on old prices.** Posting is refused when an item's price data is more than an hour old (new option), and Post all marked / Post all high-margin skip such items, along with any item that would earn less than vendoring it. Scan your bags to refresh.

## 1.0.1

- The vendor mark is now **green** (it was grey and hard to read); the AH mark stays gold.
- The **Sell marked** button moved below the merchant window so it no longer covers the repair buttons.
- **Scan progress bar** under the Auction House window: shows what a scan is doing (requesting the list from the server with an elapsed timer, reading auctions with a percentage, pricing bag items n/total), reminds you to keep the Auction House open, and ends with a green "you can close the Auction House" message or a red explanation if the scan failed, timed out or was cancelled.
- Closing the Auction House mid-scan now says so plainly in chat.
- The first-run scan prompt and Quick Start window mention that the Auction House has to stay open until the scan finishes.

## 1.0.0

First release, for the WoW Forever (Midnight retail) client.

- **Tooltips:** AH value (per unit, and per stack), estimated deposit, margin, and a "Worth auctioning" or "Vendor it" recommendation on item tooltips. Compact mode when Auctionator already prices the item.
- **Sell Panel** beside the Auction House Sell tab: sortable and filterable list of every sellable bag item with vendor, market and suggested price, profit net of deposit, margin and data age; one-click Post; Post all high-margin and Post all marked with a confirmation dialog; ignore list.
- **Scanner:** full auction house scan (chunked so the client does not freeze), scan of just your bag items, and reuse of the client's cached snapshot. Throttle-aware, with progress messages. Automatic bag scan when the AH opens.
- **Profit model** that includes the 5 percent AH cut and the listing deposit (measured: 60 percent of vendor value at 24 hours, 1 silver minimum per listing).
- **Marks:** Alt + left-click a bag item to cycle Auction, Vendor, none, with `AH` and `V` badges on the item. A "Sell marked" button below the merchant window sells exactly the vendor-marked items. Soulbound items can only be marked for the vendor.
- **Alerts:** minimap button with a count and a thin gold bag border for newly looted items worth auctioning; deferred during combat; de-duplicated; optional chat line and sound.
- **Options panel** (`/aa` or Game Menu > Options > AddOns) covering thresholds, deposit weighting, duration, pricing strategy, market value tuning, scanning, tooltips, alerts and marks.
- **First run:** a Quick Start window and an offer to run a full scan at the Auction House.
- Money shown with the game's gold, silver and copper icons.

Defaults: match market value, 8 hour listings, scan bag items automatically when the AH opens.
