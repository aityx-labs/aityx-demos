# App icon

A house with a dollar sign, in the aityx palette: an orange (`#E36742`)
house with a chimney on the dark background (`#17161A`), and a bold dollar
sign cut out of it in the background color. Solid shapes, so it still reads
as a 16 px favicon.

- **Masters:** SVGs in
  [mortgagehub_app/assets/icon/](../mortgagehub_app/assets/icon), rendered
  to 1024×1024 PNGs with headless Chrome.
  - `icon.png` is the full, opaque icon, used for iOS, web and legacy
    Android.
  - `icon_foreground.png` is the art on transparency, used for Android's
    adaptive-icon foreground layer.
- **Generated** by `flutter_launcher_icons` (configured in `pubspec.yaml`;
  rerun with `dart run flutter_launcher_icons` after editing the masters):
  - **Web:** `favicon.png`, `Icon-192/512` and their maskable variants, and
    the manifest's background and theme colors (`#17161A`).
  - **Android:** `mipmap-*/launcher_icon.png`, plus an adaptive icon
    (background `#17161A`). Flutter's default `ic_launcher.png` icons were
    removed.
  - **iOS:** the whole `AppIcon.appiconset`, with alpha removed.

## Favicon

The browser tab shows [web/favicon.svg](../mortgagehub_app/web/favicon.svg): the
same art as the icon, in [aityx.ai](https://aityx.ai)'s own favicon
style, one flat orange (`#E36742`) glyph with no background, the cutouts
transparent, so it sits beside aityx's tab like one of its family and
reads on light and dark tab strips. `index.html` links it first, as
`image/svg+xml`, and keeps `favicon.png`, the dark tile, for a browser
that can't show an SVG favicon. The app icons (the manifest's, Android's
and iOS's) keep the tile: a launcher icon needs its background.

## Name

The app is **Mortgage Hub** wherever people see its name: the browser tab
and web manifest, Android's launcher label and iOS's display name.

## Known limitations

- The Android and iOS icons haven't been seen on a device.
