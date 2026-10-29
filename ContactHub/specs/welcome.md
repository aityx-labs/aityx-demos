# Welcome page

[WelcomeScreen](../contacthub_app/lib/welcome/welcome_screen.dart) is the
app's home. Centered, at most 560 px wide:

- a speech-bubbles icon (`Icons.forum_outlined`) in the theme's primary
  color;
- **Welcome to Contact Hub**, bold;
- "Ask anything, and we get it to the right person.", muted;
- the [request box](request.md): a field for the request, typed or
  dictated with the microphone beside it, or picked from **Try a
  sample**, and **Send**, which opens the [routing](routing.md);
- the build's version, `X.Y.Z` (see
  [Development environment](dev-environment.md)), small and faint, only
  when the build sets `CONTACTHUB_VERSION`.

The [app icon](app-icon.md) is a routed speech bubble. The browser tab,
the web app's manifest, and the Android, iOS and Linux
app names say **Contact Hub**.

## Known limitations

- English only.
- No sign-in.
