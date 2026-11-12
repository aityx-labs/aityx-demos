# The key form

A demo opened without an aityx key asks for it itself, in a small form
where it calls aityx, instead of sending the user to the index page. It
is aityx_web's `AityxKeyPrompt`
([packages/aityx_web](../../packages/aityx_web/README.md#the-key-form)),
shared by every aityx demo.

The form sits under the app bar (**Play**, **Step** and the other
controls, whose every generation is an aityx call) and above the board, at
the left, in [life_screen.dart](../cellfie_app/lib/life/life_screen.dart).
While it shows, the board is that much shorter.

## When it shows

Only when there is no key at all: none saved in the browser (on the index
page, or in any demo's form) and no dev key on the index server. With a
key, the form isn't there and takes no room. It goes away as soon as a key
is set, here or on the index page in another tab, and comes back when the
key is forgotten there.

## What it holds

- **Your aityx key**: the key, never shown as typed.
- **URL (optional)**: the aityx URL, `https://api.aityx.ai` when empty;
  else an https URL on a host under aityx.ai.
- **Save** (Enter in a field does the same).
- Under them, **Get a key in the aityx console**, which opens
  `https://console.aityx.ai` in a new tab.

In a window narrower than 440 px the key takes a line of its own, with
the URL and **Save** under it.

## Saving

**Save** checks the key with aityx first, as the index page does: one
empty POST to `<url>/v1/systemone`, which aityx answers with 400
`invalid_request` once it has accepted the key, without running a model.
Only a key aityx accepts is saved, in the browser's `localStorage`
(`aityx.key`, with `aityx.url` when it isn't the default), where the
index page and every aityx demo read it: the index page then shows the
key as set, and the status light turns green. A generation asked for
without a key still pauses playback and says so in a snackbar (see [aityx
calls](aityx-calls.md#what-the-user-sees-when-it-fails)); the snackbar has
no button of its own, since the form is on the screen.

| When | The form says |
|---|---|
| nothing typed | `Paste your key first.` |
| the key has spaces | `That doesn't look like a key: it has spaces in it.` |
| the URL isn't an https URL on aityx.ai | `The URL must be an https URL on aityx.ai, like https://api.aityx.ai.` |
| aityx answers 401 or 403 | `aityx rejected the key. Not saved.` |
| no answer | `aityx did not answer (the network, or the URL is wrong). Not saved.` |
| the browser refuses the storage | `aityx accepts the key, but this browser could not save it.` |

The key is never shown, logged or put in a URL, and it is sent only to
the aityx URL of the form.
