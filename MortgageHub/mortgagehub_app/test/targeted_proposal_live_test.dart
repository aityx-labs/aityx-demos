/// Fill random's targets checked by the real regulatory check: requests
/// built for each verdict, sent to the running API (and aityx). Tagged
/// `aityx`: skipped by `flutter test`; run it with
/// `flutter test --run-skipped --tags aityx` while `devbox services up`
/// runs (API_URL overrides http://localhost:8881).
@Tags(['aityx'])
library;

import 'dart:io';

import 'package:faker/faker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mortgagehub_app/proposal/proposal_check.dart';
import 'package:mortgagehub_app/proposal/targeted_proposal.dart';

const perTarget = 30;

void main() {
  final checker = ApiProposalChecker(
    baseUrl: Platform.environment['API_URL'] ?? 'http://localhost:8881',
  );
  tearDownAll(checker.close);

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
