# Welcome page

[WelcomeScreen](../mortgagehub_app/lib/welcome/welcome_screen.dart) is the
app's home. Centered, at most 480 px wide:

- a house icon (`Icons.home_work_outlined`) in the theme's primary color;
- **Welcome to Mortgage Hub**, bold;
- "Your mortgage, from application to closing, in one place.", muted;
- a **Request a mortgage proposal** button, which opens the
  [proposal request](proposal-request.md);
- **aityx demos**, behind a left arrow: a small, muted link back to the
  index page (`/demos/` on the page's origin: https://aityx.ai/demos/ on
  the aityx website), in the same tab; primary and underlined under the
  pointer, and not shown when the app is embedded (`?embed=1`). It is
  `AityxDemosLink`, from the shared
  [aityx_web](../../packages/aityx_web/README.md) package;
- the build's version, `X.Y.Z` (see
  [Development environment](dev-environment.md)), small and faint, only
  when the build sets `MORTGAGEHUB_VERSION`.

The browser tab and the web app's manifest say **Mortgage Hub**.

## Known limitations

- English only.
- No sign-in.
