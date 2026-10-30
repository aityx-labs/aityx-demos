#!/usr/bin/env bash
# Starts the six aityx demos: Mortgage Hub, Contact Hub,
# PokerFace, RoboRules, Cellfie and RiverRace: every folder whose group.id.txt says
# `aityx`, through start-all.sh, which builds each one's web app if it is
# stale and starts the index (Index/), which serves them all on one
# origin: http://localhost:8800/ and http://localhost:8800/<slug>/
# (/mortgagehub/, /pokerface/, ...). The demos start and stop by group; use
# ./start-all.sh for every demo (the other group and the index page too)
# and ./stop-aityx.sh for the reverse.
#
#   ./start-aityx.sh              # the whole group
#   ./start-aityx.sh PokerFace    # only these (and the index), which must be in the group
exec env DEMOS_GROUP=aityx "$(cd "$(dirname "$0")" && pwd)/start-all.sh" "$@"
