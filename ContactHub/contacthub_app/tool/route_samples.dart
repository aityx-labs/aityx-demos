/// Routes every sample request (lib/request/samples.dart) on aityx, as the
/// app does (lib/aityx/), and prints where each went, what the policy
/// offered and what aityx read, against where the sample says it should
/// go. Run it in contacthub_app/:
///
///   dart run tool/route_samples.dart [--save DIR]
///
/// The key and URL are AITYX_API_KEY and AITYX_URL from the environment,
/// else from the repository's .env (../../.env); the key is never printed.
/// With --save, each routing is written to DIR as <title>.json, in the
/// shape the routing screen reads ({"routing", "aityx"}), which is how
/// test/fixtures/route-tablet.json is made. Exits 1 when a sample went
/// elsewhere.
library;

import 'dart:convert';
import 'dart:io';

import 'package:contacthub_app/aityx/routing.dart';
import 'package:contacthub_app/request/samples.dart';
import 'package:http/http.dart' as http;

/// [name] from the environment, else from the repository's .env.
String _setting(String name) {
  final value = Platform.environment[name] ?? '';
  if (value.isNotEmpty) return value;
  final env = File('../../.env');
  if (!env.existsSync()) return '';
  for (final line in env.readAsLinesSync().reversed) {
    if (line.startsWith('$name=')) return line.substring(name.length + 1);
  }
  return '';
}

Future<void> main(List<String> args) async {
  String? save;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--save':
        save = args[++i];
      default:
        stderr.writeln('unknown argument: ${args[i]}');
        exit(2);
    }
  }
  final key = _setting('AITYX_API_KEY');
  if (key.isEmpty) {
    stderr.writeln("error: AITYX_API_KEY isn't set (see ../../.env.example)");
    exit(1);
  }
  final url = _setting('AITYX_URL');
  final systemone = Uri.parse(url.isEmpty ? 'https://api.aityx.ai' : url)
      .resolve('/v1/systemone');
  final model = (jsonDecode(
    File('assets/models/routing.json').readAsStringSync(),
  ) as Map).cast<String, Object?>();
  if (save != null) Directory(save).createSync(recursive: true);
  final client = http.Client();
  var wrong = 0;
  for (final sample in [
    ...policySamples,
    ...departmentSamples,
    ...checkSamples,
  ]) {
    final sent = routingRequest(model, sample.text);
    final response = await client.post(
      systemone,
      headers: {
        'Authorization': 'Bearer $key',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(sent),
    );
    final text = utf8.decode(response.bodyBytes);
    if (response.statusCode != 200) {
      stdout.writeln('✗ ${sample.title}: HTTP ${response.statusCode} $text');
      wrong++;
      continue;
    }
    final answer = (jsonDecode(text) as Map).cast<String, Object?>();
    final Map<String, Object?> r;
    try {
      r = toRouting(sent, answer);
    } on RoutingFailed catch (error) {
      stdout.writeln('✗ ${sample.title}: $error');
      wrong++;
      continue;
    }
    final department = (r['department'] as Map)['name'] as String;
    final policy = r['policy'] as Map?;
    final topic = r['topic'] as Map;
    final read =
        '${topic['choice']} ${((topic['confidence'] as num) * 100).round()}% '
        '${r['request_kind']}';
    final expected = sample.department.split(' · ').first;
    final ok = department == expected;
    if (!ok) wrong++;
    stdout.writeln(
      '${ok ? '✓' : '✗'} ${sample.title.padRight(34)} '
      '${department.padRight(22)} '
      '${(policy?['resolution'] as String? ?? '').padRight(22)} '
      '${(policy?['refund_amount'] as num?)?.toStringAsFixed(2).padLeft(8) ?? ''.padLeft(8)} '
      '${r['priority']}${r['needs_review'] == true ? ', review' : ''}  '
      '$read'
      '${ok ? '' : '   expected $expected'}',
    );
    if (save != null) {
      final name = sample.title
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
      File('$save/$name.json')
          .writeAsStringSync(jsonEncode(withAityx(r, sent, answer, text, key)));
    }
  }
  client.close();
  stdout.writeln(
    wrong == 0 ? 'All routed as expected.' : '$wrong went elsewhere.',
  );
  exit(wrong == 0 ? 0 : 1);
}
