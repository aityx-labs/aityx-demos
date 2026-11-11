# aityx-demos

Each demo has its own `CLAUDE.md` and `AGENTS.md`; follow the one in the
demo's folder as well as this file.

## Tag every cloud resource with its demo

Every resource a demo creates in AWS (or any other cloud) carries the
account's cost-allocation tags, so its cost shows up under that demo:

- `project`: the demo's own name, lowercase (`pokertour`, `tatyx`, ...).
  Never share a project tag between demos.
- `tenancy`: `GA` (production, the default), `RC` or `shared` (serving
  more than one tenancy), set from a `<DEMO>_TENANCY` setting.

Put the tags in the deploy scripts, not only on the live resources, so
every deploy keeps them:

- Pass them as the CloudFormation stack's tags (`aws cloudformation deploy
  ... --tags project=<demo> tenancy=$tenancy`); CloudFormation copies stack
  tags to every resource that takes tags.
- Tag anything the script makes outside a stack (a code bucket, a
  parameter, a secret) explicitly, e.g. `aws s3api put-bucket-tagging`.
- See `PokerTour/deploy/deploy.sh` and `tatyx/deploy/deploy.sh`.

When adding cloud resources to a demo, or a new demo that deploys, check
that they are tagged before calling the work done: `aws
resourcegroupstaggingapi get-resources --tag-filters Key=project,Values=<demo>`
lists what has the tag, and Cost Explorer only counts costs whose
resources had the tag when they ran.
