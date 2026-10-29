# App icon

A database cylinder in the aityx palette, with its catalog cut into it:
orange (`#E36742`) on the dark background (`#17161A`), the lid and a band
cut as curved slots, and a lineage, one source branching to two, cut
into the body, all in the background color. The data and what datyx
keeps about it. Solid shapes, so it still reads at 16 px.

- **Masters:** SVGs in
  [datyx_dashboard/assets/icon/](../datyx_dashboard/assets/icon),
  rendered to 1024×1024 PNGs with headless Chrome
  (`--headless=new --screenshot --window-size=1024,1024
  --default-background-color=00000000`, on a page that shows the SVG at
  that size with no margin).
  - `icon.png` is the full, opaque icon, the one the web uses.
  - `icon_foreground.png` is the cylinder on transparency, ready for an
    Android adaptive icon should the dashboard ever get that platform.
- **Generated** by `flutter_launcher_icons` (configured in `pubspec.yaml`
  for the web only, the dashboard's one platform; rerun with
  `dart run flutter_launcher_icons` after editing the masters):
  `favicon.png`, `Icon-192/512` and their maskable variants, and the
  manifest's background and theme colors (`#17161A`, the page's, in place
  of Flutter's blue).

## Favicon

The browser tab shows
[web/favicon.svg](../datyx_dashboard/web/favicon.svg): the cylinder of
the icon redrawn in [aityx.ai](https://aityx.ai)'s own favicon style, one
flat orange (`#E36742`) path with no background, the slots and the
lineage transparent, so it sits beside aityx's tab like one of its family
and reads on light and dark tab strips. `index.html` links the PNG first
and the SVG after it, as `image/svg+xml`, so a browser that can show an
SVG favicon takes it and one that can't keeps `favicon.png`, the dark
tile. The manifest's icons keep the tile: an installed app's icon needs
its background.

## Known limitations

- The datyx API's Swagger UI, the API's own page, keeps Quarkus's
  favicon; this icon is the dashboard's.
