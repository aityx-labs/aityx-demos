# Calls panel

[CallsPanel](../cellfie_app/lib/calls/calls_panel.dart): the side panel
with every call to aityx, newest first (the last 100), under the header
**aityx calls** with their count and a button that clears them. Under
the header, where the board stands: `Generation N · M cells · aityx
answered in T ms` (see [Board](board.md#controls)). Before any call,
the panel says what the demo is and what aityx does in it, as two short
paragraphs of muted, centered text (scrolling when the panel is short):
Conway's Game of Life on an infinite board, its rules (Conway's,
HighLife's, Life without death) and a catalogue of known patterns as an
aityx decision model; then that each generation is one aityx call, the
board going in and which cells live, die or are born and which clusters
are known patterns coming back, the calls showing here on Play or Step.
A last line, in italics, reads *In memory of John Horton Conway*, his
name a link (url_launcher's `Link`, a real link on the web) to
[his Wikipedia page](https://en.wikipedia.org/wiki/John_Horton_Conway),
opened in a new tab. The first call replaces it with the cards
below.

## Width

On windows 1000 px wide or more the panel sits on the right of the
board, 440 px wide at the start. Its left edge
([ResizableSidePanel](../cellfie_app/lib/calls/resizable_side_panel.dart))
is a handle, a divider with a grip in its middle and a column-resize
cursor, colored while hovered, dragged or focused: drag it left to widen
the panel (the edge stays under the pointer) and read the requests, right to narrow it, from 360 px to
all but 320 px of the window, which stays for the board. A double-click
on it goes back to 440 px; focused, the left and right arrow keys move it
40 px. The width lasts until the page is reloaded. On narrower windows
the panel is a drawer, 440 px wide or 92% of the window, as before.

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
in Contact Hub). A button copies each side as exact JSON.

## Anchors

The key parts of each side are anchors
([requestAnchors and responseAnchors](../cellfie_app/lib/calls/calls_panel.dart)),
each a path, a label and what the part is:

- in the request, what changes every generation first (it comes last in
  the JSON, after the model): the board's situations (`state.situations`),
  the clusters and their shapes (`state.clusters`), the rules that are on
  (`state.rules`); then the model: the rules of Life
  (`decision.functions.fate.body`), the pattern catalogue
  (`decision.functions.identify.body`), the kinds of pattern
  (`decision.functions.kind_of.body`) and what is asked
  (`decision.decisions`);
- in the response: the fate of each situation (`answers.fates`), alive
  next (`answers.alive_next`), the cells alive next
  (`answers.population_next`), the pattern and the kind of each cluster
  (`answers.patterns`, `answers.kinds`), the rule that fired per
  situation (`receipt.functions.fate`), the catalogue row that matched
  (`receipt.functions.identify`) and the tokens (`usage`).

Every anchor the JSON has is tinted, with its label at the end of its
first row, and listed as a chip in a **Jump to** row above the pane (its
tooltip says what the part is). Tapping a chip, or the label in the code,
scrolls the pane so the value's first row is at the top under one row of
context, back to the left edge, marks the whole value (a stronger tint,
a primary bar and line numbers), brings the pane into view in the panel,
and shows above the pane the label, the path and line, and what the part
is. The pane has room below its last row, so a part near the end scrolls
to the top like any other.


## Known limitations

- The JSON panes are laid out when a card is opened; opening the request
  of a call with the full catalogue takes a moment.
- A call's request repeats the whole model each time; the panel shows it
  as sent.
