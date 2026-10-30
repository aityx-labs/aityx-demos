import 'package:aityx_web/aityx_web.dart';
import 'package:contacthub_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The app with aityx_web's status light, checking [store]'s key against
/// an aityx that answers [status] and [body] to the check's empty POST.
Future<void> pumpWith(
  WidgetTester tester,
  AityxKeyStore store, {
  int status = 400,
  String body = '{"code":"invalid_request"}',
}) async {
  final aityx = MockClient((request) async {
    expect(request.url, Uri.parse('https://api.aityx.ai/v1/systemone'));
    return http.Response(body, status);
  });
  await tester.pumpWidget(
    ContactHubApp(
      aityxLight: AityxStatusLight(client: aityx, store: store),
    ),
  );
  // The check's result, then the frame that shows it.
  await tester.pump();
  await tester.pump();
}

String tooltip(WidgetTester tester) => tester
    .widget<Tooltip>(
      find.descendant(
        of: find.byType(AityxStatusLight),
        matching: find.byType(Tooltip),
      ),
    )
    .message!;

AityxKeyStore withKey() => AityxKeyStore.memory(local: {'aityx.key': 'k'});

void main() {
  testWidgets('ready when aityx accepts the key the index page set', (
    tester,
  ) async {
    await pumpWith(tester, withKey());
    expect(tooltip(tester), 'aityx: ready (your key, https://api.aityx.ai)');
  });

  testWidgets('says to set a key on the index page without one', (
    tester,
  ) async {
    await pumpWith(tester, AityxKeyStore.memory());
    expect(tooltip(tester), 'aityx: no key — set yours on the index page');
  });

  testWidgets('says when aityx rejects the key', (tester) async {
    await pumpWith(tester, withKey(), status: 401, body: '{}');
    expect(tooltip(tester), startsWith('aityx: key rejected'));
  });

  testWidgets('sits at the top right, on the welcome screen', (tester) async {
    await pumpWith(tester, AityxKeyStore.memory());
    final light = tester.getRect(
      find.descendant(
        of: find.byType(AityxStatusLight),
        matching: find.byType(Container),
      ),
    );
    final screen = tester.getRect(find.byType(WelcomeScreen));
    expect(light.top, closeTo(screen.top + 6, 0.5));
    expect(light.right, closeTo(screen.right - 6, 0.5));
    expect(light.width, 8);
  });
}
