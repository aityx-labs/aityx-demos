#!/usr/bin/env bash
# Stops the six aityx demos: Mortgage Hub, Contact Hub,
# PokerFace, RoboRules, Cellfie and RiverRace, by stopping the index
# (Index/) that serves them all: every folder whose group.id.txt says
# `aityx` and runs services, through stop-all.sh. The demos start and stop by group; use
# ./stop-all.sh for every demo (the other group and the index page too)
# and ./start-aityx.sh for the reverse.
#
#   ./stop-aityx.sh              # the whole group
#   ./stop-aityx.sh Index        # only these, which must be in the group (here, the same)
exec env DEMOS_GROUP=aityx "$(cd "$(dirname "$0")" && pwd)/stop-all.sh" "$@"
