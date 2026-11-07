# Changelog

## 1.0.0

First release, for the WoW Forever (Midnight retail) client.

- **Tooltips:** AH value (per unit, and per stack), estimated deposit, margin, and a "Worth auctioning" or "Vendor it" recommendation on item tooltips. Compact mode when Auctionator already prices the item.
- **Sell Panel** beside the Auction House Sell tab: sortable and filterable list of every sellable bag item with vendor, market and suggested price, profit net of deposit, margin and data age; one-click Post; Post all high-margin and Post all marked with a confirmation dialog; ignore list.
- **Scanner:** full auction house scan (chunked so the client does not freeze), scan of just your bag items, and reuse of the client's cached snapshot. Throttle-aware, with progress messages. Automatic bag scan when the AH opens.
- **Profit model** that includes the 5 percent AH cut and the listing deposit (measured: 60 percent of vendor value at 24 hours, 1 silver minimum per listing).
- **Marks:** Alt + left-click a bag item to cycle Auction, Vendor, none, with `AH` and `V` badges on the item. A "Sell marked" button in the merchant window sells exactly the vendor-marked items. Soulbound items can only be marked for the vendor.
- **Alerts:** minimap button with a count and a thin gold bag border for newly looted items worth auctioning; deferred during combat; de-duplicated; optional chat line and sound.
- **Options panel** (`/aa` or Game Menu > Options > AddOns) covering thresholds, deposit weighting, duration, pricing strategy, market value tuning, scanning, tooltips, alerts and marks.
- **First run:** a Quick Start window and an offer to run a full scan at the Auction House.
- Money shown with the game's gold, silver and copper icons.

Defaults: match market value, 8 hour listings, scan bag items automatically when the AH opens.
