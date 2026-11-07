#!/usr/bin/env python3
"""Build dist/AuctionAgent-<version>-forever.zip from the AuctionAgent/ folder.

The version comes from the TOC. Paths inside the zip use forward slashes and start with
AuctionAgent/, so it extracts straight into Interface/AddOns.
"""
import pathlib
import re
import zipfile

root = pathlib.Path(__file__).resolve().parent.parent
addon = root / "AuctionAgent"
toc = (addon / "AuctionAgent.toc").read_text(encoding="utf-8")
match = re.search(r"^## Version:\s*(\S+)", toc, re.M)
if not match:
    raise SystemExit("No '## Version:' line in the TOC")
version = match.group(1)

out = root / "dist" / f"AuctionAgent-{version}-forever.zip"
out.parent.mkdir(exist_ok=True)
if out.exists():
    out.unlink()

files = sorted(p for p in addon.rglob("*") if p.is_file())
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
    for p in files:
        zf.write(p, "AuctionAgent/" + p.relative_to(addon).as_posix())

print(f"{out.relative_to(root)}: {len(files)} files, {out.stat().st_size} bytes")
