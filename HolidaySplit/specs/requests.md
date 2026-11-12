# Requests

The history of the requests that shaped Holiday Split, newest last. The
feature files in this folder describe the software as it is now.

## 2026-11-12

1. **Is there a free LLM a web app can use, as Contact Hub does, to parse
   free text into an aityx request?** Contact Hub's questions run on aityx,
   in the same call as the decision; they answer yes/no, choice and score,
   but don't extract values (names, amounts, dates). For
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
3. **Keep the Thanksgiving case as is; make the Christmas party a little
   bigger and more complicated, and New Year's really big and difficult to
   calculate. Don't mention Jev, only aityx. Remove the "Read the chat on
   this device" button: let the user edit the chat, and process it with
   transformers.js.** Thanksgiving at Mom's is unchanged. Christmas at the
   cabin now has 12 people (three kids at free, half and full price, a late
   couple, an uncle and his son from the 25th, two grocery runs, two drinks
   bills, sledding passes), and New Year's at the lake 15 (two lodgings,
   five kids from a baby to a 19-year-old who can't drink, early leavers and
   late arrivals, three who don't drink, a 40th birthday the others cover,
   seven expenses with cents); both settle on aityx to the cent, checked by
   hand ([The page](page.md#the-samples)). Every sample's call was recorded
   again, Thanksgiving's with the same results. The page says aityx
   wherever it said Jev, the decision's own descriptions too; aityx's
   identifiers keep their names (`"model": "jev-latest"`, `"source":
   "jev"`). The button is gone: the chat is always editable, and **Split
   it** reads a changed chat into the lists ("aityx is reading the chat"),
   then settles it; without a key the amounts are the browser's estimate
   until one is set ([Trip reader](trip-reader.md)).
4. **How could it be more precise? Use the best thing that works in the
   browser without cost (only aityx is being shown: no paid LLM). On
   Chrome, use Gemini Nano; elsewhere, the next best thing; and when the
   text wasn't changed at all, a predefined function that is exactly
   precise.** The [trip reader](trip-reader.md) now has three ways. A
   story's own text, untouched or changed back, uses the story's own lists:
   nothing is read. A rewritten chat is read by the browser's built-in
   model through the Prompt API, in one JSON answer held to a schema; where
   there is none, by LFM2 2.6B with transformers.js in the worker, in three
   short passes. And every answer is now held to the chat's own words by
   plain rules, which win over the model: ages in brackets, the trip's
   nights and first day, who comes late or leaves early, a kid's parents,
   who isn't coming, people the model missed, who paid each amount and
   whether it's drinks, the host. Candidates were scored on 18 test chats,
   fact by fact: with the rules, Gemini Nano and LFM2 2.6B read all 18
   right, and the 1 GB-class models 15 (an upper bound: the rules were
   written against these chats). Before, the reader got 1 of the nine
   stories right.
5. **In each story, make the text box larger so the chat fits, and break
   the chat into paragraphs so it's easier to understand.** The chat box is
   now as high as its text, at any width, and grows as you type: no
   scrolling inside it. Each of the nine stories' chats is split into two
   to five short paragraphs (the place and the dates, who's coming, who
   comes late or isn't paying, what was spent), with no word changed or
   moved, Thanksgiving's included. Every story's call was recorded again
   with the new text, with the same results
   ([The page](page.md#the-samples)).
6. **In this and all demos, let the key be changed without going back to
   the index, inside the demo itself, with the same mechanism, so the key
   works for all demos.** The light and **Set your key** now open a key
   dialog over the page ([The aityx key](key.md#the-key-dialog)): the
   shared key form of `aityx-js`, which checks a key with aityx, saves only
   one it accepts, in the entries every aityx demo and the demos page read,
   and can forget it. (The Flutter demos get the same through `aityx_web`,
   in their own change.)
7. **Fix the review's findings on the aityx website's pull request
   (aletyx/aityx-website#33).** Three, in the trip reader and the page:
   - In "Alice stays 2 nights but Bob stays all 4 nights", Bob got Alice's
     2 nights: the whole stay's count was dropped before the counts were
     matched to the names. It is kept for the matching, and still gives no
     one fewer nights ([Trip reader](trip-reader.md#held-to-the-chat)).
   - In "Alice is coming but Bob cannot come", Alice was left out too: a
     "not coming" anywhere in a sentence counted for every name in it. It
     now counts only in the person's part of the sentence (up to a "but",
     "while", "although"...), and not when that part says first that they
     come.
   - Picking another holiday or story while the chat was being read (the
     first read downloads the model) let the old chat's lists replace the
     new story's. The reading is dropped once another one is picked
     ([The page](page.md)).
