# Holiday Split — software specification

The current specification of the product, one file per feature. Update the
feature files a request changes, and add a file when a request adds a
feature. [requests.md](requests.md) holds the history of requests that shaped
it.

## Product

Holiday Split says who owes what after a holiday trip: who pays whom, how
much and by when, with a receipt for each person that says why. A small
LLM on the device turns the family's group chat into the lists, Jev reads
who isn't paying and who doesn't drink, and the house rules, a decision
model on aityx, settle it.

## Features

- [The page](page.md): one column in five steps (connect aityx, pick the
  trip, set the house rules, everyone's receipt, the aityx call), themed by
  the holiday, with the samples and their recorded calls.
- [The aityx key](key.md): the key every aityx demo shares, set on the
  demos page, or the index server's dev key; the status light; what runs
  without a key.
- [Trip reader](trip-reader.md): the chat into the lists, by Qwen3-0.6B
  run by transformers.js in a Web Worker, held to what the chat says.
- [Settling](settling.md): Jev's questions, the house rules' decision
  model, and the receipts.
- [Development environment](dev-environment.md): the build, the tests, the
  dev server, and how the index serves it.
