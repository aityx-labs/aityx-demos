/// Where the index server (Index/bin/server.dart) and a static host (the
/// aityx website) serve the demos: everything under one prefix.
library;

/// The prefix under which the index page, each demo (`/demos/<slug>/`),
/// the dev proxy (`/demos/aityx/`) and the index's API (`/demos/api/`)
/// are served, on the origin of the page. Each demo's scripts/build.sh
/// builds its app for `/demos/<slug>/`.
const aityxDemosPath = '/demos/';

/// [path] under [aityxDemosPath]: `demosPath('aityx/config')` is
/// `/demos/aityx/config`.
String demosPath(String path) => '$aityxDemosPath$path';
