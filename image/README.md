# The dev container images

Each demo group has its own dev container, in
[.devcontainer/<group>/](../.devcontainer), and its own published image,
built from one [Containerfile](Containerfile):

| Group | Image | What it carries |
|---|---|---|
| aityx | `docker.io/aletyxcode/samples-and-demos-aityx` | Flutter, the GitHub CLI, process-compose, the packages the six aityx demos depend on (`packages/aityx_web` among them) and **their release web builds**, which the index serves at `/<slug>/` |
| datyx | `docker.io/aletyxcode/samples-and-demos-datyx` | the same tools, GraalVM (the datyx API's JDK), the API's Maven dependencies, the packages and **release web builds** of the datyx dashboard and HealthHub |

A group is the folders whose `group.id.txt` names it. A codespace
restores the builds and starts the group's demos in seconds. GitHub's
prebuilds and Actions are switched off for this organization, so the
images are built on a laptop and pushed. They live on Docker Hub, public,
because a codespace created by anyone (a user outside the organization
included) must be able to pull them, and the organization's GHCR
packages can't be made public.

## Building and pushing them

On a clean checkout of the commit the images are for (usually `main`),
with Docker running and devbox installed:

```bash
docker login -u aletyxcode          # once; a Read & Write access token
bash image/build-image.sh aityx
bash image/build-image.sh datyx
```

[build-image.sh](build-image.sh) runs `./build-all.sh` on the group's
demos (their release builds, natively), stages the builds, the pubspecs,
the Maven projects' poms and wrappers, and a manifest of each demo's
build key ([build-key.sh](build-key.sh): the git ids of what its web
build is made from: the app package, the version files, `scripts/`,
`devbox.lock` and, for an app that depends on them by path, the shared
`packages/`) in `image/context/<group>/` (git-ignored), builds the
image for `linux/amd64` (the Codespaces machines; through Docker's
emulation on Apple silicon, a few minutes for the Flutter steps) with
`--build-arg GROUP=<group>`, which picks the group's toolchain stage of
the Containerfile, and pushes it tagged with the commit and as `latest`.
`PUSH=0` builds without pushing. `IMAGE=<registry/name>` pushes somewhere
else, say a private registry while trying an image out; each dev
container pulls whatever `image` its `devcontainer.json` names.

## What a codespace does with it

- [restore-builds.sh](restore-builds.sh), run by `on-create.sh`, copies
  the build of every demo in the image whose build key is still the manifest's into
  the workspace; a demo whose app changed since the image was made is
  skipped and builds itself (`scripts/build.sh`, about a minute on 4
  cores), so an old image slows that demo down but breaks nothing. A
  change elsewhere in the demo (its README, its specs) keeps the build.
- No API binaries are in the image: the aityx demos have no APIs (each
  app calls aityx from the browser, and the index serves them all), and
  the datyx group's `scripts/build.sh` compiles its in a few seconds.
- `DEMOS_TOOLCHAIN=image` (set by `devcontainer.json`) makes
  `start-all.sh`, `stop-all.sh` and `build-all.sh` use the image's
  Flutter, process-compose and, for datyx, GraalVM instead of devbox, and
  `DEMOS_GROUP` makes them act on the container's group only.

Rebuild and push a group's image after merging changes to its demos to
`main` when you want the fast path back for the demos that changed;
nothing breaks if you don't.
