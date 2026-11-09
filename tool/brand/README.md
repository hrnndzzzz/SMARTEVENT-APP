# Brand files

`lockup-navy.pdf` and `lockup-white.pdf` are the originals as delivered:
the same mark on two grounds, each with the wordmark beneath it.

`render-navy.png` / `render-white.png` are those two rasterised at 300dpi.
They are checked in because the PDFs need a renderer and the icon script
needs pixels; regenerate them with

```
sips -s format png --resampleWidth 1250 lockup-navy.pdf --out render-navy.png
```

or any PDF rasteriser at 300dpi.

## Regenerating the icons

```
python3 tool/brand/make_icons.py tool/brand .
```

Needs Pillow. It writes, from the renders:

- `assets/brand/` — the mark keyed to transparency on both grounds, plus
  the full lockups. `BrandMark` reads `mark-on-dark.png`.
- `android/app/src/main/res/mipmap-*/ic_launcher.png` — the legacy tile,
  full-bleed navy, for Android 7 and earlier.
- `android/app/src/main/res/mipmap-*/ic_launcher_foreground.png` — the
  adaptive layer for Android 8+, which also backs the launch splash.

The mark is cropped out of the lockup on purpose: the wordmark is a grey
smear at 48dp. The adaptive layer's scale is pinned to keep the arrow's
tail inside the 33dp radius every launcher mask is guaranteed to show —
the script prints nothing about this, so if you change the fraction,
re-measure before trusting it.

The navy, `#0C295A`, is the logo's own and is declared three times: in
`values/ic_launcher_background.xml`, in the splash layer-list, and as
`BrandMark.ground`. It is deliberately not an app palette colour — the
palette changes with the theme and this artwork does not.
