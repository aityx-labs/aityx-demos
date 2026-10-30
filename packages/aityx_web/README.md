# aityx_web

aityx from the browser, shared by the six aityx demos (MortgageHub, ContactHub,
PokerFace, RoboRules, Cellfie, RiverRace). It finds the key, calls aityx's
`/v1/systemone`, and draws the status light at the top right of every screen.
There's no per-demo API: the Flutter web app calls aityx itself.

All the demos and the index page are served from one origin (the index server,
`Index/bin/server.dart`, port 8800), so a key the user sets once on the index
page works in every demo.

## Where the key comes from

`AityxSettings.resolve()` follows this order, in the browser:

1. **The user's key**, set on the index page ("Your aityx key"):
   `sessionStorage['aityx.key']` ("only this session"), else
   `localStorage['aityx.key']` ("remember on this device"). The URL comes from
   `aityx.url` in the same storage, defaulting to `https://api.aityx.ai`. The app
   calls `<url>/v1/systemone` directly, with `Authorization: Bearer <key>`.
2. **The dev key**: with no user key, the app GETs `/aityx/config` at the root of
   the origin (not under the app's base href). When the index server has a key
   (`AITYX_API_KEY` or the repo's `.env`), it answers
   `{"available": true, "url": ..., "source": ".env" | "environment"}`, never the
   key. Calls then go to `<origin>/aityx/v1/systemone`, with no Authorization
   header: the server adds the key, so it never reaches the browser.
3. **None**: `{"available": false}`, a 404, an HTML page (a static host), or no
   answer. The light is red ("aityx: no key — set yours on the index page") and
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
  show('$e'); // "aityx is not set up: set your key on the index page"
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
user's quota. A tap opens the index page's key section (`/#aityx-key`) in the same
tab.

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
