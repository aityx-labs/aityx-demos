# aityx_web

aityx from the browser, shared by the six aityx demos (MortgageHub, ContactHub,
PokerFace, RoboRules, Cellfie, RiverRace). It finds the key, calls aityx's
`/v1/systemone`, draws the status light at the top right of every screen, and
asks for the key in the app while there is none.
There's no per-demo API: the Flutter web app calls aityx itself.

All the demos and the index page are served from one origin (the index server,
`Index/bin/server.dart`, port 8800), so a key the user sets once, on the index
page or in any demo, works in every demo.

## Where the key comes from

`AityxSettings.resolve()` follows this order, in the browser:

1. **The user's key**, set on the index page ("Your aityx key") or in a demo's
   own small form ([The key form](#the-key-form)):
   `sessionStorage['aityx.key']` ("only this session"), else
   `localStorage['aityx.key']` ("remember on this device"). The URL comes from
   `aityx.url` in the same storage, defaulting to `https://api.aityx.ai`. The app
   calls `<url>/v1/systemone` directly, with `Authorization: Bearer <key>`.
2. **The dev key**: with no user key, the app GETs `/demos/aityx/config` on the
   origin (beside the index page, not under the app's base href). When the index server has a key
   (`AITYX_API_KEY` or the repo's `.env`), it answers
   `{"available": true, "url": ..., "source": ".env" | "environment"}`, never the
   key. Calls then go to `<origin>/demos/aityx/v1/systemone`, with no Authorization
   header: the server adds the key, so it never reaches the browser.
3. **None**: `{"available": false}`, a 404, an HTML page (a static host), or no
   answer. The light is red ("aityx: no key — set yours here") and
   calls throw `AityxNoKey`.

Off the web (the VM in `flutter test`, native builds) the key store is in memory
and there's no dev proxy, so there's no key unless the app or a test sets one.

## Using it in an app

In the app's `pubspec.yaml`:

```yaml
dependencies:
  aityx_web:
    path: ../../packages/aityx_web
```

The status light, on every screen:

```dart
import 'package:aityx_web/aityx_web.dart';

MaterialApp(
  builder: withAityxStatus,
  home: const HomeScreen(),
)
```

A call:

```dart
final aityx = AityxClient();

try {
  final answer = await aityx.systemone(request); // a Map, or a JSON string
  if (!answer.ok) throw MyError(answer.problem!); // "aityx rejected the key", "aityx answered HTTP 500: ..."
  use(answer.json, answer.took);
} on AityxNoKey catch (e) {
  show('$e'); // "aityx is not set up: set your key (the light, top right)"
} on AityxUnreachable catch (e) {
  show('$e'); // "aityx did not answer"; e.cause says why ("timed out after 90 s")
}
```

`AityxClient` resolves the connection on its first call and keeps it until the
stored key or URL changes; while there's no key it asks again on each call, as the
dev key may have turned up. `systemone` answers whatever aityx answers, errors
included (`status`, `json`, `text`, `took`, `code`, `detail`, `problem`); it throws
only `AityxNoKey` and `AityxUnreachable`. Show the request body in the app's calls
panel, never `connection.headers()`: they hold the key.

## The status light

`AityxStatusLight`: an 8 px dot, 6 px from the top right; grey while it checks,
green when aityx accepts the key, red otherwise, with the reason as its tooltip and
Semantics label. The check POSTs `{}` to systemone: aityx checks the key first, so a
working key gets 400 `invalid_request` without running a model, and a bad one 401.
It checks on start, right away when the key store changes (the index page, in
another tab, saves or forgets the key), and when the window regains focus at most
once every 30 s. There's no polling timer: each check spends a request of the
user's quota. A tap opens the key panel over the app (below), unless the light is given
its own `onTap`.

## The key panel

`openAityxKey(context)` opens **Your aityx key** over the app, in its topmost `Overlay` (the
light sits above the app's `Navigator`, so the panel needs none), and completes when it
closes. The light opens it on a tap; an app can too, from a button of its own. The panel
(`AityxKeyPanel`) says which key is in use (the user's, by its last four characters, never
the key; the server's dev key; or none), and has a field for a new key, its aityx URL
(optional), **Check and save**, **Forget key**, **Close** and a link to the aityx console.
**Check and save** checks the key as the key form does and saves only one aityx accepts, in
the same storage entries, so the index page and every demo use it; a key kept for this
session only stays so. **Forget key** removes the user's key from the browser. Escape or a
tap outside closes it. Embedded in another page (`?embed=1`), nothing opens: the app posts
`"aityx:key"` to the page around it, which has its own key panel.

## The link back

`AityxDemosLink`: a left arrow and "aityx demos" (`aityxDemosLabel`), the way
back from a demo to the index page. Small, in the muted colour of the app's
secondary text (the theme's `bodySmall` in `onSurfaceVariant`), the primary
colour and underlined under the pointer; `style` and `hoverColor` change that.
A tap opens `aityxDemosPage()`, `/demos/` on the page's origin
(https://aityx.ai/demos/ on the aityx website), in the same tab. Each app
places it once, where its name is: under the title in the top bar (Cellfie,
RiverRace, PokerFace), at the end of the menu bar (RoboRules), on the welcome
page (Mortgage Hub, Contact Hub).

```dart
const Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [Text('Cellfie'), AityxDemosLink()],
)
```

## The key form

`AityxKeyPrompt`: a small form for the user's key, for an app to put where it
calls aityx (just above the button that calls it, or on its opening screen).

```dart
const AityxKeyPrompt(padding: EdgeInsets.only(bottom: 16))
AityxKeyPrompt(onSaved: retry) // run the call that needed the key
```

It takes no room at all while there is a key, the user's or the index server's
dev key: with a key in the store it asks nothing, and without one it asks only
`/demos/aityx/config` (never aityx, so nothing of the user's quota). With no key
anywhere it shows the key (never as typed), the aityx URL (optional: empty is
`https://api.aityx.ai`, else an https URL on a host under aityx.ai,
`cleanAityxUrl`), **Save**, and under them **Get a key in the aityx console**,
which opens `https://console.aityx.ai` in a new tab.

**Save** checks the key with aityx the way the index page does (one empty call,
which runs no model) and saves only a key aityx accepts, in `localStorage`, where
the index page and every demo read it; the
form then goes away and `onSaved` runs. A key aityx rejects, or one it didn't
answer for, isn't saved, and the form says why. The form also goes away when
the key is set elsewhere (the index page, in another tab) and comes back when
it is forgotten there.

## Embedded

The aityx website's blueprint pages open an app in a frame, at
`/demos/<slug>/?embed=1`, beside a key form of their own (the index's
`/demos/key.html`). With `embed=1` (read once, from the URL the app loaded with)
`aityxEmbedded` is true and a tap on the light posts `aityxKeyMessage`
(`"aityx:key"`) to the page around the app instead of leaving for the index page;
the page shows its key form. `AityxDemosLink` takes no room
when `aityxEmbedded`, and an app with links of its own to the index page
hides them too, so the user stays on the blueprint page.

## Tests in the apps

Nothing in the package touches the network or the browser unless asked:

```dart
import 'package:http/testing.dart';

// A call against a MockClient, on a fixed connection:
final aityx = AityxClient(
  client: MockClient((request) async => http.Response('{"decision":"ok"}', 200)),
  connection: AityxConnection.user('test-key'),
);

// Or resolved from an in-memory key store (dev mode needs an http(s) origin):
final aityx = AityxClient(
  client: mock,
  store: AityxKeyStore.memory(local: {'aityx.key': 'test-key'}),
);

// The light, with its own client and store, or a fake check:
MaterialApp(
  builder: (context, child) => withAityxStatus(context, child,
      light: AityxStatusLight(client: mock, store: AityxKeyStore.memory())),
)
AityxStatusLight(check: () async => AityxState.noKey)

// The link back, without leaving the page:
AityxDemosLink(onTap: () => opened++)
// The key form, with its own client and store:
AityxKeyPrompt(client: mock, store: AityxKeyStore.memory())

// Or a default store for everything that isn't given one:
AityxSettings.store = AityxKeyStore.memory();
```

## Checks

```sh
flutter pub get
flutter analyze
flutter test                     # the VM
flutter test --platform chrome   # also the browser store, over real localStorage
```
