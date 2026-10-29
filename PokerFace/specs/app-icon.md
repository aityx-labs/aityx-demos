# App icon

A poker face, in the aityx palette: an orange (`#E36742`) playing card,
tilted a little, on the dark background (`#17161A`), with a spade and
the two A's cut into it in the background color, and a white poker chip
with an orange dashed edge over its bottom-right corner. Solid shapes, so
it still reads at 16 px as an orange card with a white dot.

- **Masters:** SVGs in
  [pokerface_app/assets/icon/](../pokerface_app/assets/icon), rendered
  to 1024×1024 PNGs with headless Chrome
  (`--headless=new --screenshot --window-size=1024,1024` on a page that
  shows the SVG at full size).
  - `icon.png` is the full, opaque icon, used for iOS, web and legacy
    Android.
  - `icon_foreground.png` is the art on transparency, at two thirds of
    the size, used for Android's adaptive-icon foreground layer.
- **Generated** by `flutter_launcher_icons` (configured in `pubspec.yaml`;
  rerun with `dart run flutter_launcher_icons` after editing the masters):
  - **Web:** `favicon.png`, `Icon-192/512` and their maskable variants, and
    the manifest's background and theme colors (`#17161A`).
  - **Android:** `mipmap-*/launcher_icon.png`, plus an adaptive icon
    (background `#17161A`). Flutter's default `ic_launcher.png` icons were
    removed.
  - **iOS:** the whole `AppIcon.appiconset`, with alpha removed.
- **Linux** keeps no icon of its own.

## Known limitations

- The Android and iOS icons haven't been seen on a device.
