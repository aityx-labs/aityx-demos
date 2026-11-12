# Trip reader

aityx's questions about a message are yes/no, a choice among options or a
score; they don't pull values out of it. The trip reader does: it turns the
group chat into the lists the house rules settle (who comes, for how many
nights, the kids' ages and parents, what was spent and by whom), on the
device, at no cost. The page presents it as aityx ("aityx is reading the
chat", "Getting aityx ready in your browser"), never by a model's name.

## Three ways, by what's needed

1. **The story's own words: nothing is read.** While the chat is a story's
   text, untouched or changed back, **Split it** uses the story's own lists,
   which are exact. No model starts.
2. **A rewritten chat, in a browser with a built-in model** (Chrome's and
   Edge's Prompt API, `LanguageModel`: Gemini Nano in Chrome): the page asks
   it for one JSON answer, held to a schema (`responseConstraint`), in a
   session primed with the rules and two worked examples, cloned for each
   read. The browser downloads its model itself, once, for every site; the
   page shows the progress.
3. **A rewritten chat, anywhere else**: a module Web Worker,
   [public/reader/reader-worker.js](../holidaysplit_app/public/reader/reader-worker.js),
   the way Contact Hub runs Moonshine for dictation, runs a model with
   **transformers.js 4.3.1** (from jsDelivr, at that pinned version): on
   WebGPU, **LFM2 2.6B** (`onnx-community/LFM2-2.6B-ONNX`, 4-bit weights
   with fp16 activations, about 1.6 GB); without a GPU adapter, Qwen3 0.6B
   on WASM (4-bit, about 0.9 GB), slower and less accurate. Downloaded from
   Hugging Face on the first read, with its progress, and cached by the
   browser; the worker keeps it loaded. It reads in **three short passes**
   (who comes, with the kids' ages and parents; who stays fewer nights; who
   paid each amount, which the page finds itself), because a small model is
   far more accurate on narrow questions than on one long answer. A
   built-in model that fails hands over to the worker.

[src/reader.js](../holidaysplit_app/src/reader.js) picks between 2 and 3;
the prompts, the schema and the checks are in
[public/reader/trip-reader.js](../holidaysplit_app/public/reader/trip-reader.js),
which the page and the worker both load.

## Held to the chat

Whatever the model answers is checked against the chat's own words before
it fills the lists (`toTrip`). No model is involved in any of this, and
what the chat's words settle wins over the model's answer:

- **People.** A name that isn't in the chat is left out (small models copy
  names from their examples), and so is something that isn't a name ("Hal's
  kids"). Someone the chat names only to say they aren't coming ("Cousin
  Gil can't make it") is left out, with a note, unless they paid something;
  a "not coming" is theirs only in their part of the sentence ("Alice is
  coming but Bob can't come" leaves out Bob alone), and not when the
  sentence says first that they come ("Alice is coming and Bob cannot
  come").
  People the model missed are added when the chat's wording is clear: a
  kid with an age in brackets, a parent named on a kid's line, who "brings
  his kids" or is in "Jo's daughter", whose place the first sentence says
  it is ("at Grandma June's"), and a name listed together with people
  already known ("It's Hal, Ines, Jax, Kay and Lon").
- **Ages.** The age in brackets after a name ("Lily (4)", "the twins, Ari
  and Eli (7)"); else the model's, only when the chat gives it right after
  the name ("eli who's 9"). An age of 21 or more isn't kept; one from 18 to
  20 is (they pay their share but can't drink).
- **Parents.** The adults named before the kid in the kid's sentence: one
  after "Jo's", "his" or "her"; both after "their"; else the adults listed
  together ("Jan and Mo are bringing the kids"). Else the model's. A kid
  under 18 with no parent in the lists counts as an adult, with a note.
- **Nights.** The trip's are the most the chat counts ("5 nights from Dec
  23"). A person's are fewer when a sentence that names them counts nights
  ("Leo only makes it for the last 2 nights, and Tess comes with him"; with
  two counts, each is for the people named before it, a whole stay
  included: "Alice stays 2 nights but Bob stays all 4" shortens Alice's
  alone),
  says "a night early", or gives the day they arrive or leave ("Ruth
  arrives on the 30th"), counted from the first day. The model's word for
  fewer nights is taken only for someone the chat says comes late or
  leaves early. A kid stays no longer than the parent who stays longest.
- **The first day.** The model's when the chat writes that date, else the
  first date the chat writes; the next time that day comes.
- **Expenses.** Only amounts written in the chat (`$1,850`, `$42.50`), as
  many times as it writes them. Who paid is the one named with a verb
  before the amount ("Mo did the grocery run, $420"; a second amount of
  the sentence is theirs too), else who booked or paid right after ("$2,450.
  Sam booked it and paid", "on Hana's card"); else the model's. It's drinks
  when the words about it are of alcohol, and only then. A label whose
  words aren't in the chat's words about the amount is replaced by those.
  An amount the model missed is filled in when the chat says who paid it;
  else a note says so: "$90 is in the chat but not in the lists: add it
  below".
- **The host.** "At Mom's", "Hal's name is on the booking", "Sam booked
  it"; else the model's, else who paid for the lodging.

Nothing to split (no one to pay, or no amount) is an error, shown under the
chat. Then the lists are replaced, the trip is labeled **Your trip**, and,
as for a story, aityx reads the chat for who isn't paying and who doesn't
drink, and settles it (see [Settling](settling.md)); without a key, the
page shows the browser's own estimate and asks for one. Every list stays
editable, and the page asks to check them.

## Measured

On 18 test chats, the nine stories and nine others written less tidily
(lowercase, a guest who isn't coming, a booker who didn't pay), scored
fact by fact (each person, their nights, age and parents; each amount, its
payer and whether it's drinks; the first day; the host), in headless
Chrome on an Apple-silicon Mac:

| Reader | Chats fully right | Facts right |
|---|---|---|
| Chrome's built-in model (Gemini Nano), one JSON answer | 18 of 18 | 100% |
| LFM2 2.6B, three passes (WebGPU, 1.6 GB) | 18 of 18 | 100% |
| gemma 3 1B, three passes (0.7 GB) | 16 of 18 | 98.8% |
| Llama 3.2 1B, three passes (1.0 GB) | 15 of 18 | 99.3% |
| LFM2 1.2B, three passes (0.7 GB) | 15 of 18 | 98.1% |
| Qwen3 0.6B, three passes (0.5 GB) | 4 of 18 | 95.3% |

**Read these as an upper bound.** The checks above were written while
looking at these same chats, so they fit them; a chat worded differently
will fall back on the model more, and the models alone are much weaker.
Before the checks, on a six-chat sample: the same small models got 72 to
90% of facts in three passes and 51 to 74% in one JSON answer, with no
chat fully right; Gemini Nano with only the first checks (ages, nights,
parents) got 15 of 18. The first reader, Qwen3 0.6B in one JSON answer,
got 1 of the nine stories.

Ruled out: Qwen3 1.7B (its 1.4 GB single file doesn't load in a browser:
`std::bad_alloc`), granite 4.0 1B (4-bit fp16 weights answer only "!!!!" on
WebGPU), LFM2 1.2B Extract (repeats the worked example), and Qwen3's
thinking mode (slower and worse).

Speed of one read, the model already loaded, in the same headless Chrome
(about 11 tokens a second for both): Gemini Nano, 15 to 21 s for a story
of five to eight people and 29 to 38 s for the 12- and 15-person ones;
LFM2 2.6B, 10 to 12 s and 18 to 26 s (its three passes write about half as
much). Before the first read of a visit: about a minute for Chrome to
start a session with its built-in model, about half a minute for the
worker to load LFM2 from the browser's cache.

In the app itself, the 15-person New Year's story with a guest and an
expense added was read by both, into the same 16 people and 8 expenses,
and settled by aityx to the same cents. A browser whose built-in model
can't start (Chrome for Testing) handed over to the worker.

## Limits

- The model and the library come from Hugging Face and jsDelivr on the
  first read (or the browser fetches its own built-in model): the chat
  stays on the device, but those sites see the download. The worker runs
  on the app's origin, the one that holds the aityx key; it can't read
  `localStorage` or `sessionStorage`, and it is never sent the key.
- English chats, US dollars. The wording rules are English.
- A first read is slow: the model's download (1.6 GB for the worker's;
  several GB, by the browser, for Chrome's built-in one), then seconds to
  a minute to read.
- Without WebGPU, the worker falls back to Qwen3 0.6B on WASM, the
  weakest reader measured (4 of 18 on WebGPU), and too slow to be of use:
  one five-person chat took over seven minutes on the CPU in headless
  Chrome (20 of its 23 facts right). LFM2's 4-bit weights don't run on
  WASM at all. A browser with neither a built-in model nor WebGPU is
  better served by fixing the lists by hand.
- The built-in model was run in the installed Chrome, headless, with a
  profile of its own; not yet in a window by hand.
