# App icon

The game in pixels: the yellow plane (`#E8E84A`) and its missile over the
blue river (`#1C3FAA`), between green banks (`#4E8F2A`), on a 16 × 16 grid.
Solid shapes, so it still reads at 16 px.

- **Masters:** SVGs in
  [riverrace_app/assets/icon/](../riverrace_app/assets/icon), rendered
  to 1024×1024 PNGs with headless Chrome
  (`--headless=new --screenshot --window-size=1024,1024
  --default-background-color=00000000`).
  - `icon.png` is the full, opaque icon, used for iOS, web and legacy
    Android.
  - `icon_foreground.png` is the plane on transparency, used for Android's
    adaptive-icon foreground layer.
- **Generated** by `flutter_launcher_icons` (configured in `pubspec.yaml`;
  rerun with `dart run flutter_launcher_icons` after editing the masters):
  - **Web:** `favicon.png`, `Icon-192/512` and their maskable variants, and
    the manifest's background and theme colors (`#17161A`).
  - **Android:** `mipmap-*/launcher_icon.png`, plus an adaptive icon
    (background the river's blue, `#1C3FAA`).
  - **iOS:** the whole `AppIcon.appiconset`, with alpha removed.
- **Linux** keeps no icon of its own.

## Known limitations

- The Android and iOS icons haven't been seen on a device.
