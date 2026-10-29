/// Routes every sample request (lib/request/samples.dart) through a running
/// API and prints where each went, what the policy offered and what aityx
/// read, against where the sample says it should go:
///
///   dart run tool/route_samples.dart [--api http://localhost:8891] [--save DIR]
///
/// With --save, each API answer is written to DIR as <title>.json, which is
/// how the test fixtures are made. Exits 1 when a sample went elsewhere.
library;

import 'dart:convert';
import 'dart:io';

import 'package:contacthub_app/request/samples.dart';

Future<void> main(List<String> args) async {
  var api = 'http://localhost:8891';
  String? save;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--api':
        api = args[++i];
      case '--save':
        save = args[++i];
      default:
        stderr.writeln('unknown argument: ${args[i]}');
        exit(2);
    }
  }
  if (save != null) Directory(save).createSync(recursive: true);
  final client = HttpClient();
  var wrong = 0;
  for (final sample in [
    ...policySamples,
    ...departmentSamples,
    ...checkSamples,
  ]) {
    final request = await client.postUrl(Uri.parse('$api/api/route'));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'message': sample.text}));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      stdout.writeln('✗ ${sample.title}: HTTP ${response.statusCode} $text');
      wrong++;
      continue;
    }
    final json = jsonDecode(text) as Map;
    final r = json['routing'] as Map;
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
      File('$save/$name.json').writeAsStringSync(text);
    }
  }
  client.close();
  stdout.writeln(
    wrong == 0 ? 'All routed as expected.' : '$wrong went elsewhere.',
  );
  exit(wrong == 0 ? 0 : 1);
}
