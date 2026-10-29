import 'voice_input.dart';

/// Android, iOS, Linux and tests: no voice input yet.
class PlatformVoiceInput implements VoiceInput {
  @override
  Future<VoiceEngine> engine() async => VoiceEngine.unsupported;

  @override
  void start({
    required void Function(VoiceState state, double? progress) onState,
    required void Function(String text, bool isFinal) onText,
    required void Function(String message) onError,
  }) {
    onError('Voice input is not available here.');
    onState(VoiceState.idle, null);
  }

  @override
  void stop() {}
}
