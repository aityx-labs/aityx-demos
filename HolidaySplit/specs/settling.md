# Settling

Two aityx calls per trip, from the page itself
([src/main.js](../holidaysplit_app/src/main.js), `readLive` and
`settleLive`), on the key described in [The aityx key](key.md):

1. **aityx reads the chat**: for each adult in the lists, one yes/no question
   (`noul`), `<id>_not_paying` (the chat says they won't pay a share: their
   house, the group's treat, a birthday), and, for each adult who may
   drink, `<id>_no_drinks`. An answer at least 0.8 likely (the decision's
   `evidence_threshold`) counts. What you set by hand wins.
2. **The house rules settle it**: the decision model `Example · Holiday
   split` (`DECISION` in main.js), with the house rules written into its
   constants (`free_age`, `half_age`, `split_by_nights`,
   `drinkers_split_drinks`, `pay_days_before`), on the state: the start,
   the host, who doesn't pay, the adults, the kids, the expenses. It answers
   the transfers (who pays whom, how much), the date to pay by and a
   receipt per person, line by line, with the rounding.

A change to a list or a rule runs only step 2 again, 350 ms after the last
change: no AI. A new chat (a sample, or one read on the device) runs both.
The page words each receipt line and marks its source.

Without a key, the samples show their recorded calls instead (see [The
page](page.md)).
