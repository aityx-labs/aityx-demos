# The page

One calm column ([index.html](../holidaysplit_app/index.html),
[src/main.js](../holidaysplit_app/src/main.js),
[src/style.css](../holidaysplit_app/src/style.css)), from the original
prototype, in five numbered steps:

1. **Connect aityx**: whether aityx accepts the key, and **Set your key**,
   which opens the key dialog
   (see [The aityx key](key.md)).
2. **Pick the trip**: a tab per holiday (Thanksgiving, Christmas, New
   Year's), **Fill random** and a menu of that holiday's stories, the
   group chat, and the lists it's settled from: who's coming (adults, and
   kids with their ages and parents, nights, who drinks) and what was spent
   (kind, label, amount, who paid). The chat box is as high as its text,
   which never scrolls inside it, and grows as you type. The chat can
   always be rewritten:
   **Split it** then reads it into the lists (see [Trip
   reader](trip-reader.md)); changed back to the story's own text, it uses
   the story's own lists again. Another holiday or story picked while the
   chat is being read drops that reading: the lists stay the new story's. With a key, the lists can be edited: **+
   Adult**, **+ Kid**, **+ Expense**.
3. **Set the house rules**: free and half-price ages, splitting lodging by
   nights, drinks only among the people who drink, days to pay by. Each
   change runs on aityx again. **Split it** shows the result.
4. **Get everyone's receipt**: who pays whom, then a receipt per person,
   each line with its source (what aityx read, a house rule, your
   input), **Copy receipt as image** and **Copy who pays whom for the group
   chat**.
5. **See the aityx call**: the house rules, the request and the response,
   as key parts or the full JSON.

The page takes the mood of the holiday (colors, fonts, garlands, fireworks
or leaves, a countdown), from Google Fonts and inline SVG and canvas.

## The samples

Nine stories, three per holiday, each with its chat (in short paragraphs:
the place and the dates, who's coming, who comes late or isn't paying,
what was spent), its lists, the host
and the outcome it shows (a kid who stays free, a host who doesn't pay,
people who leave early...). The one each holiday opens on grows with the
holiday:

- **Thanksgiving at Mom's**: 8 people, one day; Mom hosts and doesn't pay.
- **Christmas at the cabin**: 12 people over 5 nights. Three kids (4, 12
  and 16: free, half and full) for two parents, a late couple (2 nights),
  an uncle with his son from the 25th (3 nights), two who don't drink, two
  grocery runs, two drinks bills and sledding passes.
- **New Year's at the lake**: 15 people over 4 nights. Two lodgings, five
  kids across two families (from a baby, free, to a 19-year-old who pays
  full but can't drink), two who leave a night early, one who comes for 2
  nights and one from the 30th, three who don't drink, a 40th birthday the
  others cover, and seven expenses with cents, paid by five people.

Each story has a real aityx call recorded with a key
([src/recordings.json](../holidaysplit_app/src/recordings.json)), shown
when there's no key. The team can record them again: open the page with
`#record` in the address, with a key, and press **Record all examples**.

The footer links back to the aityx demos and shows the build's version,
`X.Y.Z` (X and Y from `version.X.txt` and `version.Y.txt`, Z the build
time, UTC).
