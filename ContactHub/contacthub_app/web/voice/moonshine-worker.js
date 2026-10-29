// Moonshine tiny, run by transformers.js off the page's thread (see
// voice.js). Messages in: {id, type: "load"} and {id, type: "transcribe",
// audio: Float32Array of 16 kHz mono}. Out: {id, type: "progress",
// progress: 0..1}, {id, type: "loaded"}, {id, type: "text", text},
// {id, type: "error", message}.
//
// The library comes from jsDelivr at a pinned version and the model from
// Hugging Face; both are cached by the browser, and the audio stays here.
import { pipeline } from "https://cdn.jsdelivr.net/npm/@huggingface/transformers@4.3.1";

const MODEL = "onnx-community/moonshine-tiny-ONNX";

let loading = null;

// WebGPU when the browser has a GPU adapter: the full-precision encoder
// and a 4-bit decoder (about 76 MB), as Hugging Face's Moonshine demo
// runs it. Otherwise WASM with 8-bit weights (about 28 MB).
async function settings() {
  if (navigator.gpu) {
    try {
      if (await navigator.gpu.requestAdapter()) {
        return { device: "webgpu", dtype: { encoder_model: "fp32", decoder_model_merged: "q4" } };
      }
    } catch (_) {
      // Falls back to WASM.
    }
  }
  return { device: "wasm", dtype: "q8" };
}

function load(onProgress) {
  if (!loading) {
    // Each file reports its own progress; the total is their sum.
    const files = new Map();
    loading = settings()
      .then((options) =>
        pipeline("automatic-speech-recognition", MODEL, {
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
        }),
      )
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
    const transcriber = await load((progress) =>
      self.postMessage({ id, type: "progress", progress }),
    );
    if (type === "load") {
      self.postMessage({ id, type: "loaded" });
    } else if (type === "transcribe") {
      const { text } = await transcriber(data.audio);
      self.postMessage({ id, type: "text", text });
    }
  } catch (error) {
    self.postMessage({ id, type: "error", message: error.message || String(error) });
  }
};
