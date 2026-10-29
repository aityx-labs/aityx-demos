import 'dart:async';

import 'package:contacthub_app/main.dart';
import 'package:contacthub_app/request/voice_input.dart';
import 'package:contacthub_app/routing/routing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dictation the test drives: [start] keeps the callbacks, and the test
/// calls them as the browser would.
class FakeVoice implements VoiceInput {
  FakeVoice([this.kind = VoiceEngine.localSpeech]);

  final VoiceEngine kind;
  int starts = 0;
  int stops = 0;
  late void Function(VoiceState state, double? progress) state;
  late void Function(String text, bool isFinal) text;
  late void Function(String message) error;

  @override
  Future<VoiceEngine> engine() async => kind;

  @override
  void start({
    required void Function(VoiceState state, double? progress) onState,
    required void Function(String text, bool isFinal) onText,
    required void Function(String message) onError,
  }) {
    starts++;
    state = onState;
    text = onText;
    error = onError;
  }

  @override
  void stop() => stops++;
}

/// Never answers: the test only checks the routing screen opens.
class PendingRouter implements RequestRouter {
  final asked = <String>[];

  @override
  Future<RoutingOutcome> route(String message) {
    asked.add(message);
    return Completer<RoutingOutcome>().future;
  }
}

void main() {
  Future<List<String>> pumpBox(WidgetTester tester, VoiceInput voice) async {
    final sent = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RequestBox(voice: voice, onSubmit: sent.add),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return sent;
  }

  FilledButton sendButton(WidgetTester tester) => tester.widget<FilledButton>(
    find.ancestor(of: find.text('Send'), matching: find.byType(FilledButton)),
  );

  testWidgets('sends what was typed, trimmed', (tester) async {
    final sent = await pumpBox(tester, FakeVoice());

    expect(sendButton(tester).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '  Where is my refund?  ');
    await tester.pump();
    await tester.tap(find.text('Send'));

    expect(sent, ['Where is my refund?']);
  });

  testWidgets('has no mic where voice input is unsupported', (tester) async {
    await pumpBox(tester, FakeVoice(VoiceEngine.unsupported));

    expect(find.byIcon(Icons.mic_none), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('dictates after what was typed, live', (tester) async {
    final voice = FakeVoice();
    await pumpBox(tester, voice);
    await tester.enterText(find.byType(TextField), 'Hi.');

    await tester.tap(find.byIcon(Icons.mic_none));
    voice.state(VoiceState.starting, null);
    await tester.pump();
    expect(
      find.textContaining('allow it if your browser asks'),
      findsOneWidget,
    );

    voice.state(VoiceState.listening, null);
    await tester.pump();
    expect(voice.starts, 1);
    expect(find.byIcon(Icons.stop), findsOneWidget);
    expect(find.textContaining('Listening'), findsOneWidget);

    voice.text('I need help', false);
    await tester.pump();
    expect(find.text('Hi. I need help'), findsOneWidget);
    // No sending mid-dictation.
    expect(sendButton(tester).onPressed, isNull);

    await tester.tap(find.byIcon(Icons.stop));
    expect(voice.stops, 1);
    voice.text('I need help with my bill', true);
    voice.state(VoiceState.idle, null);
    await tester.pump();

    expect(find.text('Hi. I need help with my bill'), findsOneWidget);
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
    expect(sendButton(tester).onPressed, isNotNull);
  });

  testWidgets('shows the model download and transcription', (tester) async {
    final voice = FakeVoice(VoiceEngine.model);
    await pumpBox(tester, voice);

    await tester.tap(find.byIcon(Icons.mic_none));
    voice.state(VoiceState.downloading, 0.42);
    await tester.pump();
    expect(find.textContaining('42%'), findsOneWidget);

    voice.state(VoiceState.transcribing, null);
    await tester.pump();
    expect(find.textContaining('Turning your words into text'), findsOneWidget);
  });

  testWidgets('says why dictation failed', (tester) async {
    final voice = FakeVoice();
    await pumpBox(tester, voice);

    await tester.tap(find.byIcon(Icons.mic_none));
    voice.error('Microphone access was denied.');
    voice.state(VoiceState.idle, null);
    await tester.pump();

    expect(find.text('Microphone access was denied.'), findsOneWidget);
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
  });

  testWidgets('a sample fills the field', (tester) async {
    await pumpBox(tester, FakeVoice());
    await tester.enterText(find.byType(TextField), 'something else');

    await tester.tap(find.text('Try a sample'));
    await tester.pumpAndSettle();
    expect(find.text("ORDERS: THE STORE'S POLICY"), findsOneWidget);
    await tester.tap(find.text('Return within 30 days'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('running shoes from order 113-2045'),
      findsOneWidget,
    );
    expect(sendButton(tester).onPressed, isNotNull);
  });

  testWidgets('a sample ends a dictation, whose late text is ignored', (
    tester,
  ) async {
    final voice = FakeVoice();
    await pumpBox(tester, voice);

    await tester.tap(find.byIcon(Icons.mic_none));
    voice.state(VoiceState.listening, null);
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.readOnly, isTrue);

    await tester.tap(find.text('Try a sample'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('On its way'));
    await tester.pumpAndSettle();
    expect(voice.stops, 1);

    // The stopped dictation's last words arrive late.
    voice.text('old words', true);
    voice.state(VoiceState.idle, null);
    await tester.pump();

    expect(find.textContaining('order 121-0408'), findsOneWidget);
    expect(find.textContaining('old words'), findsNothing);
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
  });

  testWidgets('sending opens the routing for the request', (tester) async {
    final router = PendingRouter();
    await tester.pumpWidget(ContactHubApp(voice: FakeVoice(), router: router));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Change my address');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(RoutingScreen), findsOneWidget);
    expect(find.text('Change my address'), findsOneWidget);
    expect(router.asked, ['Change my address']);
  });
}
