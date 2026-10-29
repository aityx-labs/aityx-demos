# Welcome page

[WelcomeScreen](../mortgagehub_app/lib/welcome/welcome_screen.dart) is the
app's home. Centered, at most 480 px wide:

- a house icon (`Icons.home_work_outlined`) in the theme's primary color;
- **Welcome to Mortgage Hub**, bold;
- "Your mortgage, from application to closing, in one place.", muted;
- a **Request a mortgage proposal** button, which opens the
  [proposal request](proposal-request.md);
- the build's version, `X.Y.Z` (see
  [Development environment](dev-environment.md)), small and faint, only
  when the build sets `MORTGAGEHUB_VERSION`.

The browser tab and the web app's manifest say **Mortgage Hub**.

## Known limitations

- English only.
- No sign-in.
