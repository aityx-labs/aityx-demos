#!/usr/bin/env bash
# Starts the datyx group: the datyx API (datyx/), the datyx
# dashboard (datyx-dashboard/) and HealthHub: every folder whose group.id.txt says
# `datyx`, through start-all.sh. The demos start and stop by group; use
# ./start-all.sh for every demo (the other group and the index page too)
# and ./stop-datyx.sh for the reverse.
#
#   ./start-datyx.sh              # the whole group
#   ./start-datyx.sh HealthHub    # only these, which must be in the group
exec env DEMOS_GROUP=datyx "$(cd "$(dirname "$0")" && pwd)/start-all.sh" "$@"
