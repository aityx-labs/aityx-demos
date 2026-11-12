# Requests

The history of the requests that shaped Holiday Split, newest last. The
feature files in this folder describe the software as it is now.

## 2026-11-12

1. **Is there a free LLM a web app can use, as Contact Hub does, to parse
   free text into an aityx request?** Contact Hub uses Jev, aityx's own LLM,
   in the same call as the decision; Jev answers yes/no, choice and score
   questions, but doesn't extract values (names, amounts, dates). For
   those, a small model run in the browser by transformers.js, as Contact
   Hub runs its speech model, is free and keeps the text on the device.
2. **Copy `holiday-split-live_v11.html` into a new demo in the aityx group,
   Holiday Split, built in the same style as the others (the same security
   mechanism, the aityx key), with transformers.js in the style of Contact
   Hub; add it to the index with a screenshot, a description and links.**
   The prototype became `holidaysplit_app/`, a Vite app: its markup,
   styles, logic, samples and recorded calls as they were
   ([The page](page.md), [Settling](settling.md)). Its own key form gave
   way to the demos' shared key through `packages/aityx_js`: the key set on
   the demos page, else the index server's dev key through its proxy, and
   the status light ([The aityx key](key.md)). The group chat, read-only
   in the prototype, can now be rewritten and read by the [trip
   reader](trip-reader.md), a small LLM run by transformers.js 4.3.1 in a
   Web Worker, whose answer is held to the chat (names and amounts it
   doesn't have are left out). The index server serves a `<slug>_app/`
   with a `package.json` as well as a Flutter one, and the index page has
   Holiday Split's card, with its recording.

   Measured in Chrome on WebGPU, over the nine samples, how many the
   reader got exactly right (people, ages, parents, nights, expenses,
   payers, start, host): Qwen3-0.6B (4-bit, about 540 MB) 1 of 9, 5 to 12 s
   each, mostly missing a person, who leaves early or a kid's second
   parent, with or without a sharper prompt; with thinking on, slower
   and worse. Qwen3-1.7B doesn't load in the browser (`std::bad_alloc`).
   So the reader is 0.6B, held to the chat, and the page asks to check
   the lists.
