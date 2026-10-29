# App icon

A tank seen from above, in the aityx palette: two tracks, a hull, a
turret ringed by a gap, and a barrel, in orange (`#E36742`) on the dark
background (`#17161A`). Solid shapes, so it still reads at 16 px.

- **Master:** [roborules_app/assets/icon/icon.svg](../roborules_app/assets/icon/icon.svg),
  1024×1024, the tank on the tile.
- **Generated** with headless Chrome from the master (the app has no
  `flutter_launcher_icons`; the web is its only platform): `web/favicon.png`
  (64 px) and `web/icons/Icon-192.png`, `Icon-512.png` and their maskable
  copies, the tile as it is. To regenerate, render the SVG at each size:

  ```bash
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new \
    --window-size=512,512 --screenshot=web/icons/Icon-512.png page.html
  ```

  where `page.html` shows the SVG at that size with no margin.
- The manifest's colors are the [window](window.md)'s, not the tile's.

## Favicon

The browser tab shows [web/favicon.svg](../roborules_app/web/favicon.svg): the
tank of the icon redrawn in [aityx.ai](https://aityx.ai)'s own favicon
style, one flat orange (`#E36742`) path with straight edges and sharp
corners and no background: the tracks set off from the hull by slots, an
octagonal turret ringed by a gap, the barrel, the cutouts transparent, so it sits beside aityx's tab like one of its family and
reads on light and dark tab strips. `index.html` links it first, as
`image/svg+xml`, and keeps `favicon.png`, the dark tile, for a browser
that can't show an SVG favicon. The app icons (the manifest's, Android's
and iOS's) keep the tile: a launcher icon needs its background.

## Known limitations

- The icons have only been seen in a browser.
