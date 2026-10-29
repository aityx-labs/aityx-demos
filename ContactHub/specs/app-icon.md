# App icon

A question being routed, in the aityx palette: an orange (`#E36742`)
speech bubble on the dark background (`#17161A`), with a route cut into
it in the background color. One line comes in from a node on the left,
branches three ways, and ends in three nodes; the middle one, the chosen
destination, is larger and white. Solid shapes and thick strokes, so it
still reads at 16 px as an orange bubble with a lit dot.

- **Masters:** SVGs in
  [contacthub_app/assets/icon/](../contacthub_app/assets/icon), rendered
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
- **Linux** keeps no icon of its own, as in Mortgage Hub.

## Favicon

The browser tab shows [web/favicon.svg](../contacthub_app/web/favicon.svg): the
same art as the icon, in [aityx.ai](https://aityx.ai)'s own favicon
style, one flat orange (`#E36742`) glyph with no background, the cutouts
transparent, so it sits beside aityx's tab like one of its family and
reads on light and dark tab strips. `index.html` links it first, as
`image/svg+xml`, and keeps `favicon.png`, the dark tile, for a browser
that can't show an SVG favicon. The app icons (the manifest's, Android's
and iOS's) keep the tile: a launcher icon needs its background.

## Known limitations

- The Android and iOS icons haven't been seen on a device.
