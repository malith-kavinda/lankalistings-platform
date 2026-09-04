# Screenshots — deliberately empty

The visual reference material for this project already lives outside the harness and is **referenced, not
copied**, so there is one source of truth:

| What | Where |
|---|---|
| 17 Stitch screen exports — rendered PNG + the Tailwind source each was compiled from | `../../../../stitch_advertising/<screen>/screen.png` and `code.html` |
| Consumer design system (serves `frontend-web` + `mobile`) | `../../../../stitch_advertising/lankalistings/DESIGN.md` |
| Operator design system (serves `management-portal`) | `../../../../stitch_advertising/lankalistings_operational_interface/DESIGN.md` |
| Rendered token reference | `../../../../stitch_advertising/visual_style_guide/` |

The screen-by-screen reading of those assets — including which are usable as-is, which conflict, and the
~11 surfaces with no design at all — is in [`../feature-inventory.md`](../feature-inventory.md) and
[`../docs/02-ux-scope.md`](../docs/02-ux-scope.md).

**Two hand-off rules worth repeating here**, because they are easy to get wrong when looking at a `code.html`:

1. **The exports are visual specifications, not shippable code.** Each is a single-file Tailwind CDN page
   with an inlined config and Material Symbols icon names. Port intent — layout, spacing, hierarchy,
   state, copy — not markup.
2. **Front-matter tokens beat prose hexes.** The consumer `DESIGN.md` prose quotes colours that do not
   match its own front-matter (e.g. prose "Deep Navy `#0F172A`" vs front-matter `primary: #000000`). The
   front-matter is what the screens compile from, so it wins.

Put genuinely new captures here — client-supplied screenshots, competitor references, whiteboard photos.
Do not copy the Stitch exports in.
