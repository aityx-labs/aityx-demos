# Contact Hub — software specification

The current specification of the product, one file per feature. Update the
feature files a request changes, and add a file when a request adds a
feature. [requests.md](requests.md) holds the history of requests that shaped
it.

## Product

Contact Hub lets someone ask anything and routes the question to the
right department or person, running the checks it needs on the way. For
now it is a welcome page where a request can be typed or dictated, on
the device, or picked from samples, and routed to the right department
by Jev and aityx.

## Features

**App**

- [Welcome page](welcome.md): the app's home, with its name, a one-line
  welcome, the request box and the build's version.
- [Request box](request.md): the request, typed or dictated with the
  microphone beside the field, or picked from **Try a sample**, and
  **Send**. Speech is recognized in the
  browser only: Chrome's and Edge's on-device Web Speech, else Moonshine
  tiny run by transformers.js in a Web Worker.
- [Routing](routing.md): Jev classifies the message and checks it, the
  routing model picks the department, the person, the priority and
  whether it's reviewed, in one aityx call the app makes itself, on the
  key set on the index page (or the index server's dev key); the screen
  shows why, with links to exactly the JSON behind each item, and the
  aityx call, large, with exact navigation.
- [Order policy](order-policy.md): for a request about an order, the
  store's policy from the order's dates and amounts (refund within 30
  days, store credit within 60, final sale, damage within 7 days, warranty,
  restocking fee, price drops, cancellations, late packages), with the
  amount and the date it's paid by; the order book of the samples.
- [aityx status light](aityx-status.md): a discreet dot at the top right
  of every screen, the aityx demos' shared light, green when aityx accepts
  the key, red when there is no key or aityx doesn't work, with why in its
  tooltip.
- [Theme](theme.md): the aityx dark palette.
- [App icon](app-icon.md): an orange speech bubble with a route that
  branches three ways, the chosen branch lit; the favicon and every
  platform's icon, generated from SVG masters.

**Project**

- [Development environment](dev-environment.md): the index server that
  serves the app at `/contacthub/`, the shared aityx_web package, devbox,
  the builds and the dev container. There's no backend of its own.

## Workflow

- Every new feature or bug fix starts on a new branch from `main`, with its
  own pull request. Nothing is pushed directly to `main`. See
  [CLAUDE.md](../CLAUDE.md).
- Every request updates the affected feature specs and the
  [request log](requests.md) in the same PR.
- Each feature file ends with its own **Known limitations**, where it has
  any.
