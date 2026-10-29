#!/usr/bin/env bash
# Starts the six aityx demos: Mortgage Hub, Contact Hub,
# PokerFace, RoboRules, Cellfie and RiverRace: every folder whose group.id.txt says
# `aityx`, through start-all.sh. The demos start and stop by group; use
# ./start-all.sh for every demo (the other group and the index page too)
# and ./stop-aityx.sh for the reverse.
#
#   ./start-aityx.sh              # the whole group
#   ./start-aityx.sh PokerFace    # only these, which must be in the group
exec env DEMOS_GROUP=aityx "$(cd "$(dirname "$0")" && pwd)/start-all.sh" "$@"
