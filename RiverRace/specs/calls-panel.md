# Calls panel

The side panel ([calls_panel.dart](../riverrace_app/lib/calls/calls_panel.dart)),
on the right on wide screens (1000 pixels and up), else in a drawer opened
by **Calls (n)** in the app bar. Its header says how many calls were made,
with a button that clears them. Before any call, it shows two paragraphs
(scrolling when the panel is short): what the demo is (the 1982 Atari
river shooter remade, two planes flown by aityx by rules you can edit,
the yellow one yours), then what aityx does and how the calls appear
(every few frames the race asks aityx what the two aityx pilots do, and
pressing **Start** shows the calls here as they happen). From the first
call on, the calls take its place.

Every call to aityx is a card, newest first; the panel keeps the latest
120. A card's header has:

- **Decision n**, the race's frame it was asked at, how long aityx took
  and the input tokens;
- per aityx pilot, in its plane's color: its strategy's name, the rule
  that fired (or *no rule*) and what it does (`dodge · slow · fire`), its
  why as a tooltip;
- or, when the decision failed, why (see [aityx calls](api.md)).

Tapping a card opens it: what each plane sensed, then the **REQUEST**
sent (`POST /v1/systemone`: each pilot's rules as a table, and what each
plane senses; the body only, never the headers, which hold the key) and
the **RESPONSE** received, each pretty-printed with line numbers and
colors in a pane of its own, the key parts tinted and labeled
(each pilot's senses, rules and action, and the rule that fired), with a
button that copies the exact JSON
([call_json_view.dart](../riverrace_app/lib/calls/call_json_view.dart)).

## Known limitations

- Only the latest 120 calls are kept: at 3 to 6 calls a second, the last
  half minute or so.
