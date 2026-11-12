# The aityx key

Holiday Split uses the key every aityx demo shares, through
[packages/aityx_js](../../packages/aityx_js/README.md)
([src/aityx.js](../holidaysplit_app/src/aityx.js)), the TypeScript twin of
the Flutter demos' `aityx_web`:

1. **The user's key**, set once on the demos page's **Your aityx key**
   (`/demos/#aityx-key`) and kept in this origin's `localStorage` or, for
   the session only, `sessionStorage`, as `aityx.key` with `aityx.url`.
   The app calls `<url>/v1/systemone` directly with it.
2. **Else the index server's dev key**: the app asks `/demos/aityx/config`
   and, when the server has a key, sends its calls to
   `/demos/aityx/v1/systemone`, where the server adds it. The key never
   reaches the page.
3. **Else none.**

The app has no key form of its own. The status light at the top right
(`mountStatusLight`) checks the key on start, when it changes (here, on the
demos page, or in another tab) and when the window regains focus: green
when aityx accepts it, red otherwise, why on hover. A click, like **Set
your key** in step 1, opens the demos page's key section; embedded
(`?embed=1`, the aityx website) it posts `aityx:key` to the page around it
instead. Step 1 says which key is in use and where it goes.

While aityx accepts a key, the page is live: the lists and the rules can
be edited, and every change runs on aityx. Without one, it shows the
samples' recorded calls, and the lists and the rules are locked; the chat
can still be rewritten and read into the lists, and the amounts are then
the browser's own estimate, said so, until a key is set. When the key
starts working, a trip already shown is run on aityx at once; when it stops, the page goes back to the recorded sample.

Step 5 shows where the call went and whose key it used ("Authorization:
Bearer <your key>", or the server's dev key added by its proxy), never the
key.
