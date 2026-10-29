# App icon

A glider, the smallest spaceship of Life, in the aityx palette: its 3 × 3
box on the dark background (`#17161A`), the five live cells orange
(`#E36742`), the four dead ones the panel shade (`#2A272E`), all rounded
squares. Solid shapes, so it still reads at 16 px as orange squares on
dark.

- **Masters:** SVGs in
  [cellfie_app/assets/icon/](../cellfie_app/assets/icon), rendered
  to 1024×1024 PNGs with headless Chrome
  (`--headless=new --screenshot --window-size=1024,1024
  --default-background-color=00000000`).
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
- **Linux** keeps no icon of its own, as in Contact Hub.

## Known limitations

- The Android and iOS icons haven't been seen on a device.
