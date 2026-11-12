# Holiday Split — software specification

The current specification of the product, one file per feature. Update the
feature files a request changes, and add a file when a request adds a
feature. [requests.md](requests.md) holds the history of requests that shaped
it.

## Product

Holiday Split says who owes what after a holiday trip: who pays whom, how
much and by when, with a receipt for each person that says why. aityx reads
the family's group chat into the lists and for who isn't paying and who
doesn't drink, and the house rules, a decision model on aityx, settle it.
The app says only aityx, never the models behind it.

## Features

- [The page](page.md): one column in five steps (connect aityx, pick the
  trip, set the house rules, everyone's receipt, the aityx call), themed by
  the holiday, with the samples and their recorded calls.
- [The aityx key](key.md): the key every aityx demo shares, set on the
  demos page, or the index server's dev key; the status light; what runs
  without a key.
- [Trip reader](trip-reader.md): the chat into the lists. A story's own
  text has its own exact lists; a rewritten chat is read on the device, by
  the browser's built-in model (Gemini Nano in Chrome) or else by LFM2 2.6B
  run by transformers.js in a Web Worker, and the answer is held to the
  chat's own words; shown as aityx.
- [Settling](settling.md): aityx's questions about the chat, the house
  rules' decision model, and the receipts.
- [Development environment](dev-environment.md): the build, the tests, the
  dev server, and how the index serves it.
