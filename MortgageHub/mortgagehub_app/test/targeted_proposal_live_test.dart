/// Fill random's targets checked by the real regulatory check: requests
/// built for each verdict, checked on aityx as the app checks them
/// (AityxProposalChecker). Tagged `aityx`: skipped by `flutter test`; run
/// it with `bash scripts/model-test.sh test/targeted_proposal_live_test.dart`,
/// which passes AITYX_API_KEY and AITYX_URL from the repository's .env.
/// 90 calls on that key.
@Tags(['aityx'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:aityx_web/aityx_web.dart';
import 'package:faker/faker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mortgagehub_app/aityx/proposal_model.dart';
import 'package:mortgagehub_app/proposal/proposal_check.dart';
import 'package:mortgagehub_app/proposal/targeted_proposal.dart';

const perTarget = 30;

void main() {
  final key = Platform.environment['AITYX_API_KEY'] ?? '';
  final aityx = AityxClient(
    connection: AityxConnection.user(
      key,
      url: Platform.environment['AITYX_URL'],
    ),
  );
  final checker = AityxProposalChecker(
    aityx: aityx,
    model: () async => jsonDecode(await File(modelAsset).readAsString()),
  );
  setUpAll(() {
    if (key.isEmpty) fail('AITYX_API_KEY is not set');
  });
  tearDownAll(aityx.close);

  for (final target in CheckStatus.values) {
    test('${target.label} requests get ${target.label}', () async {
      final faker = Faker(seed: target.index + 100);
      final misses = <String>[];
      for (var i = 0; i < perTarget; i++) {
        final request = targetedProposal(target, faker);
        final check = await checker.check(request);
        if (check.status != target) {
          final notes = check.checks
              .where((c) => c.result != CheckResult.pass)
              .map((c) => '${c.id}=${c.result.name}: ${c.reason}')
              .join('; ');
          misses.add(
            '${request.purpose.name}/${request.program.name}/'
            '${request.occupancy.name}/${request.propertyType.name} '
            'ltv ${check.ltv} dti ${check.dti} -> ${check.status.label}: $notes',
          );
        }
      }
      expect(misses, isEmpty, reason: misses.join('\n'));
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}
