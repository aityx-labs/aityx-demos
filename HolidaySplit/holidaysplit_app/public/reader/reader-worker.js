// The trip reader: a small LLM, run by transformers.js off the page's
// thread, that turns a group chat into the trip's lists (see
// trip-reader.js for the prompt and the answer, and src/reader.js for the
// page's side). The same way Contact Hub runs Moonshine for dictation
// (ContactHub/contacthub_app/web/voice/moonshine-worker.js).
//
// Messages in: {id, type: "load"} and {id, type: "read", chat, today}.
// Out: {id, type: "progress", progress: 0..1}, {id, type: "loaded", device},
// {id, type: "token", count}, {id, type: "trip", trip, text, ms},
// {id, type: "error", message}.
//
// The library comes from jsDelivr at a pinned version and the model from
// Hugging Face; the browser caches both, and the chat never leaves the
// device. The worker can't read localStorage or sessionStorage, where the
// aityx key is.
import { pipeline, TextStreamer } from "https://cdn.jsdelivr.net/npm/@huggingface/transformers@4.3.1";
import { messages, firstObject, toTrip } from "./trip-reader.js";

export const MODEL = "onnx-community/Qwen3-0.6B-ONNX";

let loading = null;
let device = "wasm";

// WebGPU when the browser has a GPU adapter: 4-bit weights with fp16
// activations (about 540 MB). Otherwise WASM with 4-bit weights.
async function settings() {
  if (navigator.gpu) {
    try {
      if (await navigator.gpu.requestAdapter()) return { device: "webgpu", dtype: "q4f16" };
    } catch (_) {
      // Falls back to WASM.
    }
  }
  return { device: "wasm", dtype: "q4" };
}

function load(onProgress) {
  if (!loading) {
    // Each file reports its own progress; the total is their sum.
    const files = new Map();
    loading = settings()
      .then((options) => {
        device = options.device;
        return pipeline("text-generation", MODEL, {
          ...options,
          progress_callback: (event) => {
            if (event.status !== "progress" || !event.total) return;
            files.set(event.file, [event.loaded, event.total]);
            let loaded = 0;
            let total = 0;
            for (const [l, t] of files.values()) {
              loaded += l;
              total += t;
            }
            onProgress(loaded / total);
          },
        });
      })
      .catch((error) => {
        loading = null;
        throw error;
      });
  }
  return loading;
}

self.onmessage = async ({ data }) => {
  const { id, type } = data;
  try {
    const generator = await load((progress) => self.postMessage({ id, type: "progress", progress }));
    if (type === "load") {
      self.postMessage({ id, type: "loaded", device });
    } else if (type === "read") {
      const started = performance.now();
      const prompt = generator.tokenizer.apply_chat_template(messages(data.chat), {
        tokenize: false,
        add_generation_prompt: true,
        enable_thinking: false,
      });
      let count = 0;
      const streamer = new TextStreamer(generator.tokenizer, {
        skip_prompt: true,
        // Each token: the text itself only comes at word breaks, and JSON has few.
        token_callback_function: () => self.postMessage({ id, type: "token", count: ++count }),
      });
      const out = await generator(prompt, { max_new_tokens: 700, do_sample: false, return_full_text: false, streamer });
      const text = out[0].generated_text;
      const trip = toTrip(firstObject(text), data.today ? new Date(data.today) : new Date(), data.chat);
      self.postMessage({ id, type: "trip", trip, text, ms: Math.round(performance.now() - started) });
    }
  } catch (error) {
    self.postMessage({ id, type: "error", message: error.message || String(error) });
  }
};
