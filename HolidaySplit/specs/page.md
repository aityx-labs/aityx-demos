# The page

One calm column ([index.html](../holidaysplit_app/index.html),
[src/main.js](../holidaysplit_app/src/main.js),
[src/style.css](../holidaysplit_app/src/style.css)), from the original
prototype, in five numbered steps:

1. **Connect aityx**: whether aityx accepts the key, and **Set your key**
   (see [The aityx key](key.md)).
2. **Pick the trip**: a tab per holiday (Thanksgiving, Christmas, New
   Year's), **Fill random** and a menu of that holiday's stories, the
   group chat, and the lists it's settled from: who's coming (adults, and
   kids with their ages and parents, nights, who drinks) and what was spent
   (kind, label, amount, who paid). With a key, the chat can be rewritten
   and read on the device (see [Trip reader](trip-reader.md)), and the
   lists edited: **+ Adult**, **+ Kid**, **+ Expense**.
3. **Set the house rules**: free and half-price ages, splitting lodging by
   nights, drinks only among the people who drink, days to pay by. Each
   change runs on aityx again. **Split it** shows the result.
4. **Get everyone's receipt**: who pays whom, then a receipt per person,
   each line with its source (the reader or Jev, a house rule, your
   input), **Copy receipt as image** and **Copy who pays whom for the group
   chat**.
5. **See the aityx call**: the house rules, the request and the response,
   as key parts or the full JSON.

The page takes the mood of the holiday (colors, fonts, garlands, fireworks
or leaves, a countdown), from Google Fonts and inline SVG and canvas.

## The samples

Nine stories, three per holiday, each with its chat, its lists, the host
and the outcome it shows (a kid who stays free, a host who doesn't pay,
people who leave early...). Each has a real aityx call recorded with a key
([src/recordings.json](../holidaysplit_app/src/recordings.json)), shown
when there's no key. The team can record them again: open the page with
`#record` in the address, with a key, and press **Record all examples**.

The footer links back to the aityx demos and shows the build's version,
`X.Y.Z` (X and Y from `version.X.txt` and `version.Y.txt`, Z the build
time, UTC).
