# App icon

A heart in the aityx palette, with a pulse line, one beat of an ECG, cut
out of it: orange (`#E36742`) on the dark background (`#17161A`), the
line in the background color. Solid shapes, so it still reads at 16 px.

- **Masters:** SVGs in
  [healthhub_app/assets/icon/](../healthhub_app/assets/icon), rendered
  to 1024×1024 PNGs with headless Chrome
  (`--headless=new --screenshot --window-size=1024,1024
  --default-background-color=00000000`, on a page that shows the SVG at
  that size with no margin).
  - `icon.png` is the full, opaque icon, used for iOS, web and legacy
    Android.
  - `icon_foreground.png` is the heart on transparency, used for
    Android's adaptive-icon foreground layer.
- **Generated** by `flutter_launcher_icons` (configured in `pubspec.yaml`;
  rerun with `dart run flutter_launcher_icons` after editing the masters):
  - **Web:** `favicon.png`, `Icon-192/512` and their maskable variants, and
    the manifest's background and theme colors (`#17161A`).
  - **Android:** `mipmap-*/launcher_icon.png`, plus an adaptive icon
    (background the page's dark, `#17161A`). Flutter's default
    `ic_launcher.png` files are gone.
  - **iOS:** the whole `AppIcon.appiconset`, with alpha removed.
- **Linux** keeps no icon of its own.

## Favicon

The browser tab shows [web/favicon.svg](../healthhub_app/web/favicon.svg):
the heart of the icon redrawn in [aityx.ai](https://aityx.ai)'s own
favicon style, one flat orange (`#E36742`) path with no background, the
pulse line transparent, so it sits beside aityx's tab like one of its
family and reads on light and dark tab strips. `index.html` links the
PNG first and the SVG after it, as `image/svg+xml`, so a browser that
can show an SVG favicon takes it and one that can't keeps `favicon.png`,
the dark tile. The app icons (the manifest's, Android's and iOS's) keep
the tile: a launcher icon needs its background.

## Known limitations

- The Android and iOS icons haven't been seen on a device.
