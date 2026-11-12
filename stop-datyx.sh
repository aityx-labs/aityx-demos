#!/usr/bin/env bash
# Stops the datyx group: the datyx API (datyx/), the datyx
# dashboard (datyx-dashboard/), HealthHub and their index page
# (datyx-index/): every folder whose group.id.txt says `datyx`, through
# stop-all.sh. The demos start and stop by group; use
# ./stop-all.sh for every demo (the other groups and their index pages too)
# and ./start-datyx.sh for the reverse.
#
#   ./stop-datyx.sh              # the whole group
#   ./stop-datyx.sh HealthHub    # only these, which must be in the group
exec env DEMOS_GROUP=datyx "$(cd "$(dirname "$0")" && pwd)/stop-all.sh" "$@"
