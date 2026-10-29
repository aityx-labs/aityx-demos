import 'dart:js_interop';

import 'voice_input.dart';

/// window.contactHubVoice, defined by web/voice/voice.js.
@JS('contactHubVoice')
external _Voice? get _voice;

extension type _Voice._(JSObject _) implements JSObject {
  external JSPromise<JSString> engine();
  external JSPromise<JSAny?> start(
    JSFunction onState,
    JSFunction onText,
    JSFunction onError,
  );
  external void stop();
}

/// The browser's voice input, through web/voice/voice.js.
class PlatformVoiceInput implements VoiceInput {
  @override
  Future<VoiceEngine> engine() async {
    final voice = _voice;
    if (voice == null) return VoiceEngine.unsupported;
    return switch ((await voice.engine().toDart).toDart) {
      'local-speech' => VoiceEngine.localSpeech,
      'model' => VoiceEngine.model,
      _ => VoiceEngine.unsupported,
    };
  }

  @override
  void start({
    required void Function(VoiceState state, double? progress) onState,
    required void Function(String text, bool isFinal) onText,
    required void Function(String message) onError,
  }) {
    final voice = _voice;
    if (voice == null) {
      onError('Voice input did not load.');
      onState(VoiceState.idle, null);
      return;
    }
    voice.start(
      ((JSString state, JSNumber progress) {
        final value = progress.toDartDouble;
        onState(
          VoiceState.values.firstWhere(
            (s) => s.name == state.toDart,
            orElse: () => VoiceState.idle,
          ),
          value < 0 ? null : value,
        );
      }).toJS,
      ((JSString text, JSBoolean isFinal) {
        onText(text.toDart, isFinal.toDart);
      }).toJS,
      ((JSString message) {
        onError(message.toDart);
      }).toJS,
    );
  }

  @override
  void stop() => _voice?.stop();
}
