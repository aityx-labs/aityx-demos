# Mortgage Hub — software specification

The current specification of the product, one file per feature. Update the
feature files a request changes, and add a file when a request adds a
feature. [requests.md](requests.md) holds the history of requests that shaped
it.

## Product

Mortgage Hub brings a home buyer's mortgage, from application to closing,
into one place. For now it is a welcome page and a form to request a
mortgage proposal.

## Features

**App**

- [Welcome page](welcome.md): the app's home, with its name, a one-line
  welcome, the **Request a mortgage proposal** button and the build's
  version.
- [Mortgage proposal request](proposal-request.md): the form with what a
  US lender needs to quote a loan (the loan, the property, the borrower),
  checked against the programs' rules, and its summary with the loan
  amount, LTV and DTI. No SSN, so it isn't a Regulation Z application.
  **Fill random** fills it with fake, valid data (the `faker` package),
  or, from its menu, data built for a chosen verdict;
  the less common fields have ⓘ tooltips.
- [Regulatory check](regulatory-check.md): the summary's verdict
  (Processable / Requires review / Not processable) under current US rules
  (Fannie Mae's matrix, 2026 FHFA and FHA limits, FHA, VA and USDA rules,
  DTI limits), executed by aityx.ai, which the app calls from the browser
  with the model it carries as an asset.
- [Theme](theme.md): the aityx dark palette ([colors](theme-colors.txt)).
- [App icon](app-icon.md): a yellow house with a dollar sign, the favicon
  and every platform's icon, generated from SVG masters.

**Integrations**

- [aityx.ai](aityx.md): the key the user sets on the index page (else
  the index server's dev key, through its proxy), the shared
  `aityx_web` package that finds it and calls aityx, the status light,
  top right on every screen, that says whether there's a key and aityx
  accepts it, and `scripts/aityx-check.sh`, which runs the docs' example
  with the repository's `.env` key. There is no backend: the
  repository's index serves the app at `/mortgagehub/`.

**Project**

- [Development environment](dev-environment.md): devbox, the build the
  index serves, the model tests, the native builds and the dev
  container.

## Workflow

- Every new feature or bug fix starts on a new branch from `main`, with its
  own pull request. Nothing is pushed directly to `main`. See
  [CLAUDE.md](../CLAUDE.md).
- Every request updates the affected feature specs and the
  [request log](requests.md) in the same PR.
- Each feature file ends with its own **Known limitations**, where it has
  any.
