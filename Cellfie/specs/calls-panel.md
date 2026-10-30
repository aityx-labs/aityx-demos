# Calls panel

[CallsPanel](../cellfie_app/lib/calls/calls_panel.dart): the side panel
with every call to aityx, newest first (the last 100), under the header
**aityx calls** with their count and a button that clears them. Before
any call, it explains that every generation is one call to aityx.

## Patterns noticed

When a pattern has appeared, the first card lists the last 8 notices,
`Generation 12: A glider appeared`, each with what the pattern is (see
[Patterns](patterns.md)). Tapping one scrolls the panel to the call that
noticed it, opens it (closing any other) and marks it with an amber
border until it's toggled; the panel holds which cards are open.

## A call

Each call is a card. Its header, which opens and closes the card:

- **Generation 12 → 13**;
- the facts: how many situations and clusters were sent, how long aityx
  took (as the app measured it, from sending the request to reading the
  whole answer) and the input tokens it counted;
- pills: `134 → 141 cells`, `+12 born` (green), `−5 died` (red),
  `129 live on` (orange), and each pattern recognized, with `×n` when
  there are several (amber).

Open, the card shows:

- **What aityx decided**: a row per situation (`Live cell, 2 neighbours
  × 9`, its fate colored by whether the cells live, and the rule that
  decided it; the rule's why as a tooltip), then a row per cluster (its
  size and shape, the pattern or *not a known pattern*, and the catalogue
  row that matched; what the pattern is as a tooltip);
- **REQUEST**: the whole body sent to `POST /v1/systemone` (the body
  only: never the headers, which hold the key);
- **RESPONSE**: the whole answer.

## The JSON

[CallJsonView](../cellfie_app/lib/calls/call_json_view.dart): each side
in a pane of its own, 320 px high, scrolling both ways: 14 px Roboto
Mono (bundled, see [assets/fonts](../cellfie_app/assets/fonts/README.md)),
22 px rows with line numbers, colors for keys, strings, numbers and
literals; short lists, such as a table's rows, stay on one line, and long
strings (the inputs' descriptions) wrap at 88 characters onto unnumbered
rows ([json_layout.dart](../cellfie_app/lib/calls/json_layout.dart), as
in Contact Hub). The key parts are tinted with a label on their first
row: in the request, the rules that are on, the board's situations, the
clusters and their shapes, the rules of Life, the pattern catalogue and what is asked; in
the response, the fate of each situation, alive next, the pattern of each
cluster, the cells alive next, the rule that fired per situation and the
catalogue row that matched. A button copies each side as exact JSON.

## Known limitations

- The JSON panes are laid out when a card is opened; opening the request
  of a call with the full catalogue takes a moment.
- A call's request repeats the whole model each time; the panel shows it
  as sent.
