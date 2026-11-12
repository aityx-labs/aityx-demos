// The trip reader for browsers without a built-in model: an LLM run by
// transformers.js off the page's thread, that turns a group chat into the
// trip's lists in three short passes (see trip-reader.js for the prompts
// and the answer, and src/reader.js for the page's side, which uses the
// browser's built-in model instead where there is one). The same way
// Contact Hub runs Moonshine for dictation
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
import { readInPasses, toTrip } from "./trip-reader.js";

// The models, chosen on a set of test chats (see specs/trip-reader.md).
// On WebGPU, LFM2 2.6B with 4-bit weights and fp16 activations (about
// 1.6 GB). Without a GPU adapter, a model small enough for WASM: Qwen3
// 0.6B with 4-bit weights (about 0.9 GB), slower and less accurate.
const ON_WEBGPU = { model: "onnx-community/LFM2-2.6B-ONNX", device: "webgpu", dtype: "q4f16" };
const ON_WASM = { model: "onnx-community/Qwen3-0.6B-ONNX", device: "wasm", dtype: "q4" };

let loading = null;
let device = "wasm";

async function settings() {
  if (navigator.gpu) {
    try {
      if (await navigator.gpu.requestAdapter()) return ON_WEBGPU;
    } catch (_) {
      // Falls back to WASM.
    }
  }
  return ON_WASM;
}

function load(onProgress) {
  if (!loading) {
    // Each file reports its own progress; the total is their sum.
    const files = new Map();
    loading = settings()
      .then(({ model, ...options }) => {
        device = options.device;
        return pipeline("text-generation", model, {
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
      self.postMessage({ id, type: "loaded", device });
      let count = 0;
      const said = [];
      // One pass: the messages in, the model's text out, each token counted.
      const ask = async (messages) => {
        const prompt = generator.tokenizer.apply_chat_template(messages, {
          tokenize: false,
          add_generation_prompt: true,
          enable_thinking: false,
        });
        const streamer = new TextStreamer(generator.tokenizer, {
          skip_prompt: true,
          callback_function: () => {},
          // Each token: the text itself only comes at word breaks.
          token_callback_function: () => self.postMessage({ id, type: "token", count: ++count }),
        });
        const out = await generator(prompt, {
          max_new_tokens: 500,
          do_sample: false,
          return_full_text: false,
          // The template has the special tokens already.
          add_special_tokens: false,
          streamer,
        });
        said.push(out[0].generated_text);
        return out[0].generated_text;
      };
      const answer = await readInPasses(data.chat, ask);
      const trip = toTrip(answer, data.today ? new Date(data.today) : new Date(), data.chat);
      self.postMessage({ id, type: "trip", trip, text: said.join("\n\n"), ms: Math.round(performance.now() - started) });
    }
  } catch (error) {
    self.postMessage({ id, type: "error", message: error.message || String(error) });
  }
};
