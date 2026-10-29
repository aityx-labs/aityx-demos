// Contact Hub's voice input, in the browser and on the device only: no
// audio leaves it. Exposes window.contactHubVoice, which the Flutter app
// calls through dart:js_interop (lib/request/voice_input_web.dart).
//
// Two engines, the first one this browser has:
//   "local-speech"  the Web Speech API with processLocally = true (Chrome,
//                   Edge): live words as you speak. Chrome downloads its
//                   language pack once, through SpeechRecognition.install().
//   "model"         Moonshine tiny, a speech model built for edge devices,
//                   run by transformers.js in a Web Worker
//                   (moonshine-worker.js), on WebGPU or else WASM: records
//                   until you stop, then transcribes. The model downloads
//                   once and the browser caches it.
// The Web Speech API's default mode is never used: it sends the audio to
// a server.
//
// Add ?voice=model to the page's URL to force the model (for testing).
(() => {
  "use strict";

  const LANG = "en-US";
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  const forced = new URLSearchParams(location.search).get("voice");

  let engine = null; // "local-speech" | "model" | "unsupported"
  let session = null; // the running dictation, with its stop()
  let worker = null;

  function hasMicrophone() {
    return !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia);
  }

  function canRunModel() {
    return hasMicrophone() && typeof Worker !== "undefined" &&
      typeof WebAssembly !== "undefined";
  }

  // The engine to use; asks the browser once.
  async function detect() {
    if (engine) return engine;
    if (forced !== "model" && SR && typeof SR.available === "function") {
      try {
        const status = await SR.available({ langs: [LANG], processLocally: true });
        if (status !== "unavailable") return (engine = "local-speech");
      } catch (_) {
        // Falls through to the model.
      }
    }
    return (engine = canRunModel() ? "model" : "unsupported");
  }

  // --- local-speech --------------------------------------------------------

  async function startLocalSpeech(cb) {
    const options = { langs: [LANG], processLocally: true };
    const status = await SR.available(options);
    if (status === "downloadable" || status === "downloading") {
      cb.onState("downloading", -1);
      const installed = await SR.install(options);
      if (!installed) throw new Error("This browser could not install its speech model.");
    }
    const recognition = new SR();
    recognition.lang = LANG;
    recognition.processLocally = true;
    recognition.continuous = true;
    recognition.interimResults = true;
    cb.onState("starting", -1);

    let finalText = "";
    recognition.onstart = () => cb.onState("listening", -1);
    recognition.onresult = (event) => {
      let interim = "";
      for (let i = event.resultIndex; i < event.results.length; i++) {
        const result = event.results[i];
        if (result.isFinal) finalText = join(finalText, result[0].transcript);
        else interim = join(interim, result[0].transcript);
      }
      cb.onText(join(finalText, interim), false);
    };
    recognition.onerror = (event) => {
      if (event.error === "no-speech" || event.error === "aborted") return;
      cb.onError(speechError(event.error));
    };
    recognition.onend = () => {
      session = null;
      cb.onText(finalText, true);
      cb.onState("idle", -1);
    };
    recognition.start();
    return { stop: () => recognition.stop() };
  }

  function speechError(code) {
    switch (code) {
      case "not-allowed":
      case "service-not-allowed":
        return "Microphone access was denied.";
      case "audio-capture":
        return "No microphone was found.";
      case "language-not-supported":
        return "This browser can't recognize English on this device.";
      default:
        return `Speech recognition failed (${code}).`;
    }
  }

  // --- model ---------------------------------------------------------------

  // The worker's unanswered requests, by id, to fail them all if it dies.
  const pending = new Map();

  function getWorker() {
    if (!worker) {
      worker = new Worker(new URL("voice/moonshine-worker.js", document.baseURI), {
        type: "module",
      });
      // A worker that can't load (its library unreachable, say) never
      // answers: fail what's waiting, and start afresh next time.
      worker.onerror = (event) => {
        event.preventDefault();
        const message = "The speech model could not load. Check the connection and try again.";
        for (const { reject } of pending.values()) reject(new Error(message));
        pending.clear();
        worker.terminate();
        worker = null;
      };
    }
    return worker;
  }

  // Sends one request to the worker and resolves with its answer, reporting
  // download progress on the way.
  function ask(message, onProgress) {
    const w = getWorker();
    const id = Math.random().toString(36).slice(2);
    return new Promise((resolve, reject) => {
      const listener = ({ data }) => {
        if (data.id !== id) return;
        if (data.type === "progress") return onProgress(data.progress);
        w.removeEventListener("message", listener);
        pending.delete(id);
        if (data.type === "error") reject(new Error(data.message));
        else resolve(data);
      };
      pending.set(id, {
        reject: (error) => {
          w.removeEventListener("message", listener);
          reject(error);
        },
      });
      w.addEventListener("message", listener);
      w.postMessage({ ...message, id }, message.audio ? [message.audio.buffer] : []);
    });
  }

  async function startModel(cb) {
    // Load the model first, so the first dictation isn't recorded while it
    // downloads; later dictations find it loaded.
    cb.onState("downloading", 0);
    await ask({ type: "load" }, (p) => cb.onState("downloading", p));

    cb.onState("starting", -1);
    let stream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    } catch (error) {
      throw new Error(error && error.name === "NotAllowedError"
        ? "Microphone access was denied."
        : "No microphone was found.");
    }
    const recorder = new MediaRecorder(stream);
    const chunks = [];
    recorder.ondataavailable = (event) => event.data.size && chunks.push(event.data);
    recorder.onstop = async () => {
      stream.getTracks().forEach((track) => track.stop());
      session = null;
      try {
        cb.onState("transcribing", -1);
        const audio = await toMono16k(new Blob(chunks, { type: recorder.mimeType }));
        const { text } = await ask({ type: "transcribe", audio }, () => {});
        cb.onText(text.trim(), true);
      } catch (error) {
        cb.onError(`Transcription failed: ${error.message}`);
      } finally {
        cb.onState("idle", -1);
      }
    };
    recorder.start();
    cb.onState("listening", -1);
    return { stop: () => recorder.state !== "inactive" && recorder.stop() };
  }

  // The recording as 16 kHz mono samples, which Moonshine expects.
  async function toMono16k(blob) {
    const context = new AudioContext({ sampleRate: 16000 });
    try {
      const decoded = await context.decodeAudioData(await blob.arrayBuffer());
      if (decoded.numberOfChannels === 1) return decoded.getChannelData(0);
      const mono = new Float32Array(decoded.length);
      for (let c = 0; c < decoded.numberOfChannels; c++) {
        const channel = decoded.getChannelData(c);
        for (let i = 0; i < mono.length; i++) mono[i] += channel[i] / decoded.numberOfChannels;
      }
      return mono;
    } finally {
      context.close();
    }
  }

  // --- shared --------------------------------------------------------------

  function join(a, b) {
    a = (a || "").trim();
    b = (b || "").trim();
    return a && b ? `${a} ${b}` : a || b;
  }

  window.contactHubVoice = {
    // "local-speech", "model" or "unsupported".
    engine: detect,

    // Starts dictating. Callbacks:
    //   onState(state, progress)  "downloading" (progress 0..1, or -1 when
    //                             unknown), "starting" (opening the
    //                             microphone; the browser may ask for
    //                             permission), "listening", "transcribing",
    //                             "idle" (done, after the final text)
    //   onText(text, isFinal)     the words so far; isFinal once, at the end
    //   onError(message)          then "idle"
    async start(onState, onText, onError) {
      if (session) return;
      const cb = { onState, onText, onError };
      try {
        const kind = await detect();
        if (kind === "unsupported") throw new Error("This browser can't record audio.");
        session = { stop() {} }; // a stop before it's started is kept below
        let stopped = false;
        session.stop = () => (stopped = true);
        const running = kind === "local-speech" ? await startLocalSpeech(cb) : await startModel(cb);
        session = running;
        if (stopped) running.stop();
      } catch (error) {
        session = null;
        cb.onError(error.message || String(error));
        cb.onState("idle", -1);
      }
    },

    stop() {
      if (session) session.stop();
    },
  };
})();
