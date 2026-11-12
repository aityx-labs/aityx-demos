#!/usr/bin/env bash
# Stops the multyx group: Poker Tour (PokerTour/), the tatyx game
# (tatyx/) and their index page (multyx-index/): every folder whose
# group.id.txt says `multyx`, through stop-all.sh. The demos start and
# stop by group; use ./stop-all.sh for every demo (the other groups and
# their index pages too) and ./start-multyx.sh for the reverse.
#
#   ./stop-multyx.sh              # the whole group
#   ./stop-multyx.sh PokerTour    # only these, which must be in the group
exec env DEMOS_GROUP=multyx "$(cd "$(dirname "$0")" && pwd)/stop-all.sh" "$@"
