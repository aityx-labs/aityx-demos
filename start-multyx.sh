#!/usr/bin/env bash
# Starts the multyx group: Poker Tour (PokerTour/), the tatyx game
# (tatyx/) and their index page (multyx-index/): every folder whose
# group.id.txt says `multyx`, through start-all.sh. The demos start and
# stop by group; use ./start-all.sh for every demo (the other groups and
# their index pages too) and ./stop-multyx.sh for the reverse.
#
#   ./start-multyx.sh              # the whole group
#   ./start-multyx.sh PokerTour    # only these, which must be in the group
exec env DEMOS_GROUP=multyx "$(cd "$(dirname "$0")" && pwd)/start-all.sh" "$@"
