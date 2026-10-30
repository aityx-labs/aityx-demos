/// Runs strategies on aityx.ai with fixed situations and checks which rule
/// fires and what the plane does. Tagged `aityx`, so `flutter test` skips
/// it (dart_test.yaml); scripts/model-test.sh runs it with the key from
/// the repository's .env, which reaches this test's environment only.
@Tags(['aityx'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:aityx_web/aityx_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverrace_app/aityx/decision_request.dart';

import 'decision_request_test.dart' show calm, careful;

Future<Map<String, Object?>> ask(Map<String, Object?> sent) async {
  final env = Platform.environment;
  final client = AityxClient(
    connection: AityxConnection.user(
      env['AITYX_API_KEY'] ?? '',
      url: (env['AITYX_URL'] ?? '').isEmpty
          ? 'https://api.aityx.ai'
          : env['AITYX_URL']!,
    ),
  );
  try {
    final answer = await client.systemone(sent);
    expect(answer.status, 200, reason: answer.problem);
    return (answer.json as Map).cast<String, Object?>();
  } finally {
    client.close();
  }
}

void main() {
  final base = jsonDecode(
    File('assets/models/river.json').readAsStringSync(),
  ) as Map<String, Object?>;

  /// Both pilots fly the careful strategy, p1 in [one], p2 in [two].
  Future<Map> decide(Map<String, Object?> one, Map<String, Object?> two) async {
    final asked = requestFrom({
      'tick': 1,
      'pilots': [
        {'id': 'p1', 'rules': careful, 'sense': one},
        {'id': 'p2', 'rules': careful, 'sense': two},
      ],
    });
    final sent = decisionRequest(base, asked.pilots);
    return toActions(1, asked.pilots, await ask(sent))['actions'] as Map;
  }

  test('land ahead comes first, then a threat', () async {
    final actions = await decide(
      calm({'land_distance': 20, 'threat': 'left'}),
      calm({'threat': 'left'}),
    );
    expect(actions['p1'], containsPair('rule', 1));
    expect(actions['p1'], containsPair('steer', 'to_channel'));
    expect(actions['p2'], containsPair('rule', 2));
    expect(actions['p2'], containsPair('steer', 'dodge'));
    expect(actions['p2'], containsPair('fire', true));
  });

  test('low fuel with a depot in sight heads for it', () async {
    final actions = await decide(
      calm({'fuel': 30, 'fuel_side': 'right'}),
      calm({'fuel': 30}),
    );
    expect(actions['p1'], containsPair('rule', 3));
    expect(actions['p1'], containsPair('steer', 'to_fuel'));
    // No depot in sight: no rule, the else row the app adds.
    expect(actions['p2'], containsPair('rule', 0));
    expect(actions['p2'], containsPair('steer', 'straight'));
  });
}
