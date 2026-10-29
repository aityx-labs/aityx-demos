import 'voice_input_stub.dart'
    if (dart.library.js_interop) 'voice_input_web.dart'
    as platform;

/// How this device turns speech into text, if it can.
enum VoiceEngine {
  /// The browser's own on-device speech recognition: live words as you
  /// speak.
  localSpeech,

  /// A speech model run in the browser: transcribes when you stop.
  model,

  /// No voice input here.
  unsupported,
}

/// Where a dictation is.
enum VoiceState {
  /// Fetching the speech model or language pack, once per device.
  downloading,

  /// Opening the microphone: the browser may be asking for permission.
  starting,
  listening,

  /// The model is turning the recording into text.
  transcribing,

  /// Done: the final text, if any, has been delivered.
  idle,
}

/// Dictation, on the device only: no audio leaves it.
abstract interface class VoiceInput {
  /// The browser's voice input (web/voice/voice.js), or none elsewhere.
  factory VoiceInput() = platform.PlatformVoiceInput;

  Future<VoiceEngine> engine();

  /// Starts dictating. [onState] reports each [VoiceState], with download
  /// progress from 0 to 1 when known; [onText] the words so far, `isFinal`
  /// once at the end; [onError] a message for the user, followed by
  /// [VoiceState.idle].
  void start({
    required void Function(VoiceState state, double? progress) onState,
    required void Function(String text, bool isFinal) onText,
    required void Function(String message) onError,
  });

  void stop();
}
