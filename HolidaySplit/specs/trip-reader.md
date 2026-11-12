# Trip reader

Jev answers questions about a message (yes/no, a choice among options, a
score); it doesn't pull values out of it. The trip reader does: a small
LLM, run in the browser, turns the group chat into the lists the house
rules settle.

## How it reads

**Read the chat on this device** (step 2, with a key) sends the chat to a
module Web Worker,
[public/reader/reader-worker.js](../holidaysplit_app/public/reader/reader-worker.js),
the way Contact Hub runs Moonshine for dictation:

- **transformers.js 4.3.1**, from jsDelivr at that pinned version;
- **Qwen3-0.6B** (`onnx-community/Qwen3-0.6B-ONNX`) from Hugging Face: on
  WebGPU, 4-bit weights with fp16 activations (`q4f16`, about 540 MB);
  else WASM with 4-bit weights (`q4`), slower;
- downloaded on the first read, with its progress, and cached by the
  browser; the worker keeps it loaded for the next reads.

The prompt ([public/reader/trip-reader.js](../holidaysplit_app/public/reader/trip-reader.js))
gives the rules, two worked examples (the cabin and Grandma June's
samples) and the chat, with Qwen3's thinking off, and asks for one JSON
object: the first day (month-day), the trip's nights, the host, the people
(name, a kid's age and parents, nights) and the expenses (kind, label,
amount, who paid). Greedy decoding, at most 700 tokens. The page counts
the tokens as they come.

## Held to the chat

A model this small copies names from its examples and misses amounts, so
the answer is checked against the chat before it fills the lists
(`toTrip`):

- a person whose name isn't in the chat is left out (a title such as
  "Grandma" doesn't count as the name), and the note says so;
- an expense whose amount isn't written in the chat (`$1,850`, `$42.50`) is
  left out, and so is the same amount by the same person twice;
- an amount the chat has but no expense took is noted: "$90 is in the chat
  but not in the lists: add it below";
- a kid needs a parent who is an adult in the list, else counts as an
  adult; a kid never drinks; an adult's age isn't kept;
- nights stay between 1 and the trip's; the start is the next time that
  day comes (today if the chat gives none); the host is who the model
  named, else who paid for the lodging, else the first person;
- a payer the chat names but the people list missed is added as an adult.

Nothing to split (no adult, or no amount) is an error, shown under the
chat. Then the lists are replaced, the trip is labeled **Your trip**, and,
as for a sample, Jev reads the chat for who isn't paying and who doesn't
drink, and aityx settles it (see [Settling](settling.md)). Every list stays
editable.

## Measured

On an Apple-silicon Mac with WebGPU in Chrome: the model ready about 16 s
after the download, then 5 to 12 s a chat. Over the nine samples, it got
1 exactly right (every person, age, parent, night, expense, payer, the
start and the host); the others mostly miss one person, the nights of
whoever leaves early, or a kid's second parent. Expenses, payers, dates
and hosts are mostly right. Qwen3-1.7B (1.36 GB) doesn't load in the
browser (`std::bad_alloc` creating the session), and Qwen3's thinking mode
was slower and worse.

## Limits

- The model and the library come from Hugging Face and jsDelivr on the
  first read: the chat stays on the device, but those two sites see the
  download. The worker runs on the app's origin, the one that holds the
  aityx key; it can't read `localStorage` or `sessionStorage`, and it is
  never sent the key.
- English chats, US dollars.
- A 0.6B model gets some chats wrong (who leaves early, whose kids): the
  page asks to check the lists, and every value can be fixed by hand.
