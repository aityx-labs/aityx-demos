# Holiday Split

Holiday Split settles who owes what after a holiday trip. Pick a trip
(Thanksgiving, Christmas or New Year's) or write your own family group
chat, and the app tells everyone how much to pay, to whom, and by when,
with a receipt for each person that says why.

In the app, it's all aityx, in three steps:

1. **The chat into the lists**: who comes, for how many nights, the kids'
   ages and parents, what was spent and by whom. A story's own text has its
   own exact lists. A chat you rewrite is read on the device, at no cost:
   by the browser's built-in model where it has one (Gemini Nano in
   Chrome), else by a model run with
   [transformers.js](https://huggingface.co/docs/transformers.js), the way
   [Contact Hub](../ContactHub/) runs its speech model. Either answer is
   then checked against the chat's own words, with no model: what the
   wording settles (ages, nights, parents, who paid) wins.
2. **Questions about the chat**, answered by aityx: who isn't paying (the
   host, a birthday) and who doesn't drink.
3. **The house rules**, a decision model on [aityx](https://aityx.ai), settle
   it the same way every time: kids up to 5 stay free and up to 12 pay half,
   lodging split by nights, drinks by the people who drink, the date to pay
   by. Change a rule and aityx settles it again.

The page shows each line's source (what aityx read, a house rule or your
edit) and the aityx calls themselves. The app never names the models
behind aityx: it says aityx.

## Technology

| Part | Technology |
|---|---|
| App ([holidaysplit_app/](holidaysplit_app)) | Plain JavaScript, HTML and CSS, built with [Vite](https://vite.dev). It calls aityx itself, from the browser, through the aityx demos' shared TypeScript package, [packages/aityx_js](../packages/aityx_js/README.md) |
| Trip reader ([src/reader.js](holidaysplit_app/src/reader.js), [public/reader/](holidaysplit_app/public/reader)) | The browser's built-in model through the Prompt API (`LanguageModel`, Gemini Nano in Chrome), held to a JSON schema; else [LFM2 2.6B](https://huggingface.co/onnx-community/LFM2-2.6B-ONNX) run by transformers.js 4.3.1 in a module Web Worker on WebGPU (4-bit, about 1.6 GB, downloaded once and cached by the browser), or Qwen3 0.6B on WASM. Then plain-JavaScript checks against the chat |
| Serving | The repository's index server ([Index/](../Index)) serves the build at `/demos/holidaysplit/`, on one origin with the index page (`/demos/`) and the other aityx demos. There's no Holiday Split API |
| Dev environment | [Devbox](https://www.jetify.com/devbox) (Nix): Node 22 and curl, the same lock as tatyx's |

## Run it locally

From the repository root:

```bash
./start-all.sh HolidaySplit     # or ./start-aityx.sh for the whole group
```

That builds the app if it changed ([scripts/build.sh](scripts/build.sh):
`npm ci` when needed, then `vite build` into `holidaysplit_app/build/web`,
a second or two) and starts the index server. Open the index page,
http://localhost:8800/demos/, set your [aityx](https://aityx.ai) key in
**Your aityx key**, and open Holiday Split's card, or
http://localhost:8800/demos/holidaysplit/. The key stays in your browser,
and every aityx demo uses it. With no key of yours, the index server lends
its dev key (`AITYX_API_KEY` in the repository's `.env`) through its own
proxy, and the key never reaches the browser. Without either, the app
shows real aityx calls recorded for each sample, and the lists and the
rules stay locked.

The light at the top right says whether aityx accepts the key. A click on
it, or **Set your key** in step 1, opens the key dialog in the app itself:
set, change or forget the key there, without going back to the index page.
It's the same key, in the same place in the browser, so it works in every
aityx demo.

To write your own trip, edit the group chat in step 2 and press **Split
it**. The first time, the model is downloaded, once: by Chrome itself for
its built-in model (several GB, shared by every site), else by the page
(about 1.6 GB). Check the lists it fills in: it leaves out names and
amounts the chat doesn't have, and says which amounts in the chat it
couldn't place. Then aityx reads who isn't paying and who doesn't drink,
and settles it. The chat can be edited without a key too: then the lists
are filled, and the amounts are the browser's estimate until a key is set.
Change the chat back to the story's own text and **Split it** uses the
story's own lists again, with nothing to read.

For development with hot reload, `devbox run dev` serves the sources on
http://localhost:18811/demos/holidaysplit/ and passes the rest of `/demos/`
(the key page, the dev proxy) to the index server on 8800 (`INDEX_PORT` to
change it).

## Tests

```bash
cd holidaysplit_app
npm test          # vitest: the trip reader's prompts, and its answer held to the chat
```

`bash scripts/build.sh` builds the web app, only when it changed, with
`<base href="/demos/holidaysplit/">` in `build/web/index.html`.

## Where it came from

A single-file prototype (`holiday-split-live_v11.html`), moved into the
aityx demos as it was: the page, its samples and its recorded calls, with
the demos' key in place of its own key form, and the trip reader added.
See [specs/requests.md](specs/requests.md).

## Learn more

- [specs/](specs/README.md): the specification of every feature.
- [packages/aityx_js](../packages/aityx_js/README.md): the key, the calls and
  the status light.
