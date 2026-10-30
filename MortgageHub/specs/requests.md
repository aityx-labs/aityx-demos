# Request log

Requests that shaped the specification, oldest first. Each entry summarizes
what was asked and what changed. See [README.md](README.md) for the current
spec.

## 2026-10-13

1. **Create the Mortgage Hub app, following Presence's project structure,
   with only a welcome page.** Added the Flutter app (`mortgagehub_app`:
   web, Android, iOS, Linux) with a [welcome page](welcome.md) in the
   Gruvbox [theme](theme.md); devbox, process-compose (the web server and
   the health monitor), the build scripts, the Makefile, versioning and
   the dev container ([Development environment](dev-environment.md));
   this specification, CLAUDE.md and AGENTS.md. Presence's backend, cloud
   and deploy parts weren't copied.
2. **Use port 8880 for the web app.** The dev server
   (`FLUTTER_WEB_PORT`), its readiness probe, the health check and the dev
   container's forwarded port now default to 8880 instead of 8080, so it
   runs beside Presence's dev server.
3. **Add a button to request a mortgage proposal, with the details a US
   quote needs.** Researched what a US lender needs (Regulation Z's
   application and Loan Estimate, the agencies' pricing factors,
   Regulation B's limits on what may be asked). Added the
   [proposal request](proposal-request.md): the welcome page's button, a
   form in three sections (the loan, the property, the borrower) with its
   validation, and a summary with the loan amount, LTV and DTI. It asks
   for no SSN, so it stays a quote request, not an application.
4. **Replace Flutter's default favicon with one for the app.** Drew the
   [app icon](app-icon.md), a yellow house with a dollar sign on the
   Gruvbox background, as SVG masters, and generated the favicon, the web
   icons and the Android and iOS icons from them with
   `flutter_launcher_icons`, as Presence does.
5. **Add a "Fill random" button that fills the proposal form with random
   data, using a good Dart faker.** Added the `faker` package and
   [Fill random](proposal-request.md#fill-random) to the form's app bar:
   random, valid requests with fake contact details (example.com emails,
   555-01xx phones).
6. **Integrate with aityx.ai; for now, only check the integration works.**
   Saved the key to `.env` as `AITYX_API_KEY` (git-ignored, mode 600),
   documented it and `AITYX_URL` in `.env.example`, and added
   [scripts/aityx-check.sh](../scripts/aityx-check.sh), which runs the
   docs' example on System One. See [aityx.ai](aityx.md). The check hasn't
   run yet: which API host the stage key belongs to is unconfirmed.
7. **Check with aityx whether the proposal is valid and processable under
   current US mortgage rules, in a new section of the requested proposal.**
   Researched the current rules (Fannie Mae's Eligibility Matrix of August
   2026, the 2026 FHFA and FHA loan limits, FHA, VA and USDA eligibility,
   DTI limits) and wrote them as an aityx decision model. Added the API
   (`mortgagehub_api`, a Dart server holding the key) and the summary's
   [regulatory check](regulatory-check.md) section. Found the stage key's
   API host (`api-stage.aityx.ai`; production answers 401) and
   verified the check end to end.
8. **Add tooltips to the uncommon form fields.** ⓘ icons with an
   explanation on the less common fields of the
   [proposal request](proposal-request.md), none on plain ones like the
   name.
9. **Have Fill random leave optional fields empty at random.** HOA dues
   are now random too (taxes, insurance and savings already were).
10. **Merge, rebuild and restart.** Before merging, fixed the code
    review's findings: the rules compared a rounded LTV and DTI (97.0002%
    passed a 97% maximum), so the model now compares exact values and the
    API rounds them for display; release Android builds lacked the
    INTERNET permission; the app's HTTP client was never closed; the web
    app couldn't reach the API behind a forwarded port, so the dev server
    now proxies `/api/` on the app's own origin; and nothing tested the
    rules, so `scripts/model-test.sh` runs them on aityx with expected
    verdicts at each boundary. The app's name on Android and iOS is now
    Mortgage Hub.
11. **Add a button to show or hide the aityx request and response at the
    end of the regulatory check.** The API now returns the body it sent to
    aityx and aityx's answer with the check, and the
    [regulatory check](regulatory-check.md) ends with **Show / Hide aityx
    request and response**, showing both as JSON.
12. **Make Fill random a split button: click it, or pick the data to
    generate: Processable, Requires review or Not processable.** Added
    the menu and a generator that builds a request for each verdict
    ([Fill random for a verdict](proposal-request.md#fill-random-for-a-verdict)),
    checked live against aityx. The verdict label "Needs review" is now
    "Requires review" everywhere.

## 2026-10-15

13. **Move the Mortgage Hub dev container to the root of the repository,
    under a folder called Mortgage Hub, so people can see which app they
    are launching on Codespaces; and pass the user's own API key in.**
    GitHub only looks for dev containers at the repository root, so
    `MortgageHub/.devcontainer/` moved to
    [.devcontainer/MortgageHub/](../../.devcontainer/MortgageHub) and
    the configuration was named **Mortgage Hub** (since archived; see 35), which is
    what the Codespaces configuration list shows in a repository holding
    several samples. The Containerfile no longer assumes the repository is
    the app (its `WORKDIR` named a path that only existed in a standalone
    repository), the build context is the dev container folder alone since
    nothing is copied in, and `post-create.sh` resolves `MortgageHub/`
    from its own location. `devcontainer.json` declares `AITYX_API_KEY` as a
    Codespaces `secret`, so GitHub asks each person for their own key and
    passes it in as an environment variable, which the scripts already
    prefer over `.env`; the repository ships no key and nothing is written
    to disk in the container. `post-create.sh` reports whether the key arrived, never its
    value. See [Development environment](dev-environment.md) and
    [aityx.ai](aityx.md).

14. **Add a link to launch a codespace with 4 cores, ask only for the API
    key, default to aityx.ai, say before the launch button how to set the
    key up and that it is required, and describe the project in the dev
    container profile.** The [README](../README.md#run-it-in-a-codespace)
    now opens with how to add the `AITYX_API_KEY` Codespaces secret and
    why it is required, then an **Open in GitHub Codespaces** badge that
    pins this configuration and a 4-core machine
    (`machine=standardLinux32gb`). `devcontainer.json` asks for the key
    alone: `AITYX_URL` already defaults to `https://api.aityx.ai` and
    `ASSUMED_RATE` to 6.5 (the annual rate, in percent, behind the
    summary's payment estimate), so neither needs setting, and both stay
    overridable in `.env`. The configuration is named **Mortgage Hub** and
    carries a header describing the project with links to the repository,
    aityx.ai, aletyx.com and nu01.com.

15. **Take a look at the Greptile suggestions and fix.** Both findings on
    [Fill random for a verdict](proposal-request.md#fill-random-for-a-verdict)
    were valid. The processable generator can build a VA loan of up to
    $855,000, above the $832,750 conforming baseline, and that is correct:
    VA has no loan limit with full entitlement, so the model passes any VA
    amount. The test applied the baseline to every program, so a valid VA
    sample failed it — reproduced at seed 27, which builds an $834,000 VA
    loan. The assertion now skips VA, and the generator and this spec say
    why. Nothing checked the ratio `fitIncome` works back from the payment
    either, so four offline tests now recompute it at 6.5% from the
    finished request: that processable drafts land in the 20 to 36% they
    aim for and stay under 45%, that a targeted high ratio really does
    breach Fannie Mae's 50%, and that a targeted review ratio lands
    between the two maximums. Both were checked by mutation.

16. **The Dart extension says it cannot find a Flutter SDK in the dev
    container; add the SDK.** Devbox installs Flutter into
    `.devbox/nix/profile/default` inside the workspace, which is a
    complete SDK but is not on the PATH, so the extension saw nothing.
    Rather than bake a second Flutter into the image, which could drift
    from the one `devbox.lock` pins, `post-create.sh` now links that
    profile to `~/flutter` once `devbox install` finishes, and
    `devcontainer.json` sets `dart.flutterSdkPath` to it and adds
    `~/flutter/bin` to the PATH of every terminal. See
    [Development environment](dev-environment.md).

17. **VS Code still offers to download a Flutter SDK; put the SDK in the
    image.** The link to devbox's Flutter came only after `devbox install`,
    long after the Dart extension had looked. The Containerfile now
    installs Flutter 3.47.0, devbox.lock's version, in `/opt/flutter`,
    and `devcontainer.json` points the extension and the PATH there;
    `post-create.sh` no longer links anything.
18. **Make the web app's port public by default.** `public-port.sh`, run
    on each start, makes port 8880 public through `gh`. It is the only
    port forwarded; the API stays behind the web server's proxy. See
    [Development environment](dev-environment.md).

19. **devbox hangs at "Computing the Devbox environment" in a codespace.**
    On Linux, devbox patches Python's glibc, which builds devbox itself
    from Go source and fetches Python's build-time closure, inside the
    codespace. Nothing in the project uses Python, so it is gone from
    `devbox.json` and `devbox.lock`, and with it the patch step.

20. **In the Show aityx request and response view, highlight the most
    important parts of the long JSON, with a tooltip or overlay saying why
    each matters.** The two JSON blocks are now an annotated view
    (`aityx_json_view.dart`): the parts that explain the verdict (the
    model and its cited rules, the facts, the verdict, each check and
    reason, the figures, the receipt, the usage) are tinted, labelled, and
    explained in a tooltip on hover or tap, with **Jump to** chips that
    scroll to them in the long request and a copy button. The response
    notes follow aityx's documented shape (`answers`, `receipt` with
    `read`, `provenance`, `decisions`, `functions`, `usage`,
    `decision_error`); they were not checked against a live answer, since
    stage was behind Cloudflare WARP. See
    [Regulatory check](regulatory-check.md).

21. **Create a Docker Compose file so the app starts with `docker compose
    up`.** Added [compose.yaml](../compose.yaml) with a `web` service (the
    Flutter release web build behind nginx, which proxies `/api/`) and an
    `api` service (the API as a native executable on `scratch`), their
    Dockerfiles and the nginx config. Only the web port, 8880, is
    published, on 127.0.0.1; the aityx key reaches the API alone. See
    [Development environment](dev-environment.md).
22. **Add to the README the commands to start it with Docker Compose or
    devbox services from the root of the repository.** The repository's
    README has a *Running it locally* section:
    `docker compose -f MortgageHub/compose.yaml up --build` and
    `devbox services up -c MortgageHub`, with their stop commands. Both
    were run from the root.
23. **Add a health check** to the Docker Compose services. `api` checks
    its own `/api/health` with a new `server healthcheck` mode, `web`
    checks `/app/` and the proxied `/api/health`, and `web` waits for a
    healthy `api`. See [Development environment](dev-environment.md).
24. **Link aityx to aityx.ai wherever the READMEs mention it.** The
    plain mentions of aityx and aityx.ai in the repository README and
    this folder's README now link to https://aityx.ai; code, commands and
    existing links are left as they were.
25. **When a proposal is Not processable, mark in red, with a tooltip like
    the other highlights, where the response asserts it.** Notes can now
    apply only to some values (`when`) and be drawn in the error color
    (`alarm`). Three red notes mark `answers.status.choice`
    (`not_processable`), each failed check's value, and
    `receipt.decisions.status.value`. See
    [Regulatory check](regulatory-check.md).
26. **A lighter shade of red, and the response before the request.** The
    Not processable highlights use the theme's red lightened by a third,
    with a softer tint, and *Show aityx request and response* now shows
    aityx's response first, then the request. See
    [Regulatory check](regulatory-check.md).
27. **Check whether the store-path pre-fetch is still needed.** It isn't:
    in a clean Linux container, `devbox install` alone finished in about
    1.5 minutes and copied every path it uses from cache.nixos.org. The
    pre-fetch also downloaded debug, dev and doc outputs nothing uses.
    `post-create.sh` no longer pre-fetches.

28. **Make the port public by default and forwarded correctly, so users
    can start the codespace and open the app right away.** A new
    `post-start.sh`, run on every start, starts the services in the
    background and runs `public-port.sh`. Port 8880 is forwarded as HTTP
    and opens in the browser once. The site root now redirects to
    `/app/`: the dev server proxies `/` to the API, which answers with a
    302. See [Development environment](dev-environment.md).

29. **The port is still private; tell users to check its visibility.**
    `public-port.sh` now also runs when VS Code attaches, and skips if a
    run is still retrying. Both READMEs' codespace steps now say to check
    that port 8880 is Public in the Ports panel, and how to set it by hand.
30. **Show the Docker Compose instructions first, then devbox.** In this
    folder's README, *Run it with Docker Compose* now comes before *Run it
    locally with devbox*, and says itself how to set the aityx key. The
    repository README already listed Docker Compose first.
31. **The app should start by itself in a codespace but doesn't; keep a
    log about service initialization that can be sent.** Added
    `MortgageHub/startup.log`: the post-create, post-start and
    public-port scripts write every step to it with a UTC time and a
    tag, along with the services' own output and a watcher that records when
    the web app and the API answer, or their state after 15 minutes. It
    replaces `/tmp/mortgagehub-services.log` and `/tmp/public-port.log`
    and holds no secrets. Tested in a Linux container with a stub devbox;
    the cause of the missed start in Codespaces is still to be found
    from a real log. See [Development environment](dev-environment.md).
32. **Add the logs to .gitignore, all of them.** `startup.log` was
    already ignored by `*.log`; it's now named too, and the repository's
    root `.gitignore` ignores `*.log` and `logs/` in every sample.
33. **Add screenshots of the codespace setup to the instructions.** The
    README's *Run it in a codespace* steps now show the *New secret* form
    (with a placeholder key) and the *Create a new codespace* page, with
    a note to check that `AITYX_API_KEY` is ticked as associated with the
    repository. The repository README points to them. See
    [Development environment](dev-environment.md).
34. **Change the colors to use the same palette as the aityx website (from
    a screenshot); also save the color theme to a text file.** Replaced the
    Gruvbox theme with the aityx dark palette: near-black violet
    backgrounds, light gray text and the orange accent as primary. "Needs
    review" moved from primary to an amber tertiary so it stays distinct
    from the accent and from red. The web manifest colors and the app
    icon follow: an orange house on the page background, regenerated for
    every platform. The palette is in
    [theme-colors.txt](theme-colors.txt). See [Theme](theme.md) and
    [App icon](app-icon.md).
35. **Archive the Mortgage Hub dev container configuration and create
    one that starts all demos** (2026-10-23). `.devcontainer/MortgageHub/`
    moved to `.devcontainer/archive/MortgageHub/`, where GitHub no longer
    offers it, and the repository's default dev container,
    `.devcontainer/devcontainer.json` (**All demos**), took its place:
    the same Containerfile, `devbox install` in every demo's folder on
    creation, `./start-all.sh` on every start, the index's and the five
    web ports forwarded and made public, and `startup.log` at the root.
    The Mortgage Hub badges and the index page's card open it. See
    [Development environment](dev-environment.md).

## 2026-10-23

36. **Use custom favicons for each sample, in the same style and colors
    as aityx but related to each demo.** The tab now shows
    `web/favicon.svg`, the house with the dollar sign as a flat orange
    glyph with no background, as aityx.ai's own favicon is drawn; the
    PNG tile stays as the fallback and the app icons keep it. See
    [App icon](app-icon.md#favicon).

## 2026-10-27

37. **Improve the aityx request and response view for the demo: make it
    wider, number the JSON's lines, and navigate precisely to each
    label.** The regulatory check widens to 1100 px while the call is
    shown; each block is a fixed-height code pane with numbered lines in
    bundled Roboto Mono; a **Jump to** chip or a label scrolls the value's
    first line to the top of the code (one line of context), marks the
    whole value, and a panel above the code gives its label, path and
    why. A label goes to its own value, not its note's first match. See
    [Regulatory check](regulatory-check.md).

38. **Make the demos efficient enough for a 4-core codespace: serve a
    release build instead of running the Flutter dev server, and compile
    the API.** `devbox services up` now serves the app's release build
    with a small native web server (`mortgagehub_api/bin/web_server.dart`:
    `/app/` from `build/web`, `/api/` and `/` proxied to the API, as nginx
    does under Docker Compose) and runs the API compiled with `dart
    compile exe`; both come from `scripts/build.sh`, which builds only
    what changed and runs one Flutter web build at a time across the
    repository. Resident memory drops from about 1.2 GB to about 35 MB per
    demo, and a start after no change takes seconds. Hot reload stays
    with `WEB_MODE=debug` or `devbox run web`. See
    [Development environment](dev-environment.md).

## 2026-10-28

39. **Have the demos prebuilt in the dev container image, ready to boot, and
   push it where anyone can launch it.** Every dev container now runs the
   published image `docker.io/aletyxcode/samples-and-demos-devcontainer`
   (public on Docker Hub, since the organization's GHCR packages can't be
   public), built from `image/Containerfile` with Flutter, process-compose
   and every demo's release web build. A codespace restores the build,
   compiles the API in seconds and starts the services on the image's own
   tools (`DEMOS_TOOLCHAIN=image`, no devbox): every demo answers less than
   four minutes after the request, down from more than ten. See
   [Development environment](dev-environment.md) and `image/README.md`.

## 2026-10-29

40. **Separate the dev containers, images and Codespaces configurations by
    demo group.** Mortgage Hub now opens in the aityx group's dev
    container, **aityx demos** (`.devcontainer/aityx/`), on the group's
    image `docker.io/aletyxcode/samples-and-demos-aityx` (`bash
    image/build-image.sh aityx`), which starts it with the other aityx
    demos and the index page. The repository's default dev container,
    **All demos**, which it opened in until now, was removed, as were the
    other per-demo ones; Mortgage Hub's own stays archived. The README's
    codespace link points at the group's container. See [Development
    environment](dev-environment.md).

41. **Number the JSON lines, make the labels navigate exactly to their
    values, widen the view, and add a discreet separator between the
    response and the request.** The numbered lines, the exact jumps and
    the 1100 px width were already in the sources (request 37) but the
    demo on this machine was still serving a Docker image built before
    them; it now serves the release build of the current sources. New: a
    faint rule between the response and the request blocks. Since the
    browser still showed the old app after that (it kept the old image's
    scripts, which nginx served without cache headers), each web build now
    gives its scripts URLs of their own, and nginx sends `no-cache` too.
    See [Regulatory check](regulatory-check.md) and [Development
    environment](dev-environment.md).

## 2026-10-30

42. **Add a discreet health indicator, top right of every screen, saying
    whether the aityx key is set and aityx is reachable and answering,
    with a tooltip.** A dot (grey while checking, green, red) over the
    top right corner of every screen, with why in its tooltip; the API's
    new `GET /api/aityx` checks the key against aityx at most once a
    minute. See [aityx.ai integration](aityx.md).

43. **Run the aityx demos entirely in the browser: no per-demo API, the
    Flutter web app calls aityx itself, and every demo and the index
    share one origin, so a key the user sets once on the index page is
    reused by every demo.** The regulatory check now runs in the app
    (`AityxProposalChecker`, on the shared `packages/aityx_web`
    package's `AityxClient`): the API's mapping moved to
    `mortgagehub_app/lib/aityx/proposal_model.dart`, the model to the
    app's assets (`assets/models/proposal-check.json`), and the API's
    tests to the app's `test/` (the model scenarios still tagged `aityx`,
    run by `scripts/model-test.sh` with the repository's `.env` key).
    The check shows what it showed, with the API's wording where users
    see it, and new wording for the key: *aityx is not set up: set your
    key on the index page*, *aityx rejected the key*, *aityx did not
    answer*, *aityx answered HTTP n: ...*, and *the rules (the aityx model) didn't
    load* (loaded again on **Try again**). The payment's assumed rate is
    fixed at 6.5% (`ASSUMED_RATE` was the API's setting). The status
    light is now aityx_web's (`withAityxStatus`), which checks the key in
    the browser and opens the index page's key section on a tap. Deleted:
    `mortgagehub_api/` (the API, the web server, their Dockerfile),
    `scripts/api.sh`, `scripts/flutter-web.sh`,
    `scripts/health-check.sh`, `process-compose.yaml`, `compose.yaml`,
    `docker/`, `.dockerignore`, `API_BASE_URL`, and devbox's `web` and
    `api` scripts. `scripts/build.sh` builds only the web app, for the
    index at `/mortgagehub/`, without the CDN
    (`--no-web-resources-cdn`); the app is at
    http://localhost:8800/mortgagehub/. See [aityx.ai
    integration](aityx.md), [Regulatory check](regulatory-check.md) and
    [Development environment](dev-environment.md).
