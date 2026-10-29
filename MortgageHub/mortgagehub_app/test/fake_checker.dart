import 'package:mortgagehub_app/proposal/proposal_check.dart';
import 'package:mortgagehub_app/proposal/proposal_request.dart';

const sampleCheck = ProposalCheck(
  status: CheckStatus.needsReview,
  checks: [
    CheckItem(id: 'program', result: CheckResult.pass, reason: 'Eligible.'),
    CheckItem(id: 'ltv', result: CheckResult.pass, reason: 'Within the max.'),
    CheckItem(id: 'limit', result: CheckResult.review, reason: 'High balance.'),
    CheckItem(id: 'credit', result: CheckResult.pass, reason: 'Fits.'),
    CheckItem(id: 'dti', result: CheckResult.fail, reason: 'Too high.'),
  ],
  ltv: 80,
  maxLtv: 97,
  dti: 35.91,
  housingPayment: 3090.77,
  assumedRate: 6.5,
);

/// Answers [result], or throws [error]; counts the calls.
class FakeChecker implements ProposalChecker {
  FakeChecker({this.result = sampleCheck, this.error});

  final ProposalCheck result;
  Object? error;
  int calls = 0;
  ProposalRequest? last;

  @override
  Future<ProposalCheck> check(ProposalRequest request) async {
    calls++;
    last = request;
    if (error != null) throw error!;
    return result;
  }
}
