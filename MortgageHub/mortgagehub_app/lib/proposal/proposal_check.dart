import 'dart:convert';

import 'package:aityx_web/aityx_web.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../aityx/proposal_model.dart';
import 'proposal_request.dart';

/// The regulatory check of a proposal request: aityx.ai's verdict under
/// current US rules, which the app asks aityx for itself
/// (AityxProposalChecker).
class ProposalCheck {
  const ProposalCheck({
    required this.status,
    required this.checks,
    required this.ltv,
    required this.maxLtv,
    required this.dti,
    required this.housingPayment,
    required this.assumedRate,
    this.aityxRequest,
    this.aityxResponse,
  });

  factory ProposalCheck.fromJson(Map<String, Object?> json) {
    final figures = json['figures'] as Map<String, Object?>;
    num figure(String key) => figures[key] as num;
    final aityx = json['aityx'] as Map<String, Object?>?;
    return ProposalCheck(
      status: CheckStatus.parse(json['status'] as String),
      checks: [
        for (final check in json['checks'] as List)
          CheckItem.fromJson(check as Map<String, Object?>),
      ],
      ltv: figure('ltv').toDouble(),
      maxLtv: figure('maxLtv').toDouble(),
      dti: figure('dti').toDouble(),
      housingPayment: figure('housingPayment').toDouble(),
      assumedRate: figure('assumedRate').toDouble(),
      aityxRequest: aityx?['request'],
      aityxResponse: aityx?['response'],
    );
  }

  final CheckStatus status;
  final List<CheckItem> checks;
  final double ltv;
  final double maxLtv;
  final double dti;

  /// Estimated: principal, interest, taxes, insurance and HOA dues.
  final double housingPayment;

  /// The annual rate, in percent, the payment is estimated with.
  final double assumedRate;

  /// The body sent to aityx (the model and its inputs; the key is a
  /// header, so not in it), and aityx's answer, as JSON. Null when they
  /// were left out.
  final Object? aityxRequest;
  final Object? aityxResponse;
}

enum CheckStatus {
  processable('processable', 'Processable'),
  needsReview('needs_review', 'Requires review'),
  notProcessable('not_processable', 'Not processable');

  const CheckStatus(this.wireName, this.label);

  /// The model's name for it.
  final String wireName;
  final String label;

  static CheckStatus parse(String name) =>
      values.firstWhere((status) => status.wireName == name);
}

/// The theme color of a verdict: green, amber or red.
Color statusColor(BuildContext context, CheckStatus status) {
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    CheckStatus.processable => scheme.secondary,
    CheckStatus.needsReview => scheme.tertiary,
    CheckStatus.notProcessable => scheme.error,
  };
}

/// The icon of a verdict.
IconData statusIcon(CheckStatus status) => switch (status) {
  CheckStatus.processable => Icons.verified_outlined,
  CheckStatus.needsReview => Icons.rule,
  CheckStatus.notProcessable => Icons.block,
};

enum CheckResult { pass, review, fail }

class CheckItem {
  const CheckItem({
    required this.id,
    required this.result,
    required this.reason,
  });

  factory CheckItem.fromJson(Map<String, Object?> json) => CheckItem(
    id: json['id'] as String,
    result: CheckResult.values.byName(json['result'] as String),
    reason: json['reason'] as String,
  );

  final String id;
  final CheckResult result;
  final String reason;

  String get label => switch (id) {
    'program' => 'Program eligibility',
    'ltv' => 'Loan-to-value',
    'limit' => 'Loan limits (2026)',
    'credit' => 'Credit score',
    'dti' => 'Debt-to-income',
    _ => id,
  };
}

/// Checks a proposal request; a fake one in tests.
abstract interface class ProposalChecker {
  Future<ProposalCheck> check(ProposalRequest request);
}

/// Runs the check with aityx, from the browser: maps the request to the
/// model's inputs (lib/aityx/proposal_model.dart), without the borrower's
/// name, email or phone, posts them with the model to System One on the
/// user's key (or the index server's dev key), and maps the answers back.
class AityxProposalChecker implements ProposalChecker {
  /// [aityx] calls aityx (a new AityxClient, which finds the key, unless
  /// given); [model] loads the model (the app's asset unless given).
  AityxProposalChecker({AityxClient? aityx, Future<Object?> Function()? model})
    : _aityx = aityx ?? AityxClient(),
      _ownsAityx = aityx == null,
      _loadModel = model ?? _assetModel;

  final AityxClient _aityx;
  final bool _ownsAityx;
  final Future<Object?> Function() _loadModel;
  Future<Object?>? _model;

  static Future<Object?> _assetModel() async =>
      jsonDecode(await rootBundle.loadString(modelAsset));

  /// Closes the AityxClient it made; one passed in is the caller's.
  void close() {
    if (_ownsAityx) _aityx.close();
  }

  @override
  Future<ProposalCheck> check(ProposalRequest request) async {
    final Map<String, Object?> state;
    try {
      // Through JSON, as the request reached the API before.
      final json = jsonDecode(jsonEncode(request.toJson()));
      if (json is! Map<String, Object?>) {
        throw InvalidRequest('expected an object');
      }
      state = toState(json, assumedRate);
    } on InvalidRequest catch (error) {
      throw ProposalCheckException(error.message);
    }
    final Object? model;
    try {
      model = await (_model ??= _loadModel());
    } catch (_) {
      // Loaded again on Try again, rather than failing for good.
      _model = null;
      throw ProposalCheckException("the rules (the aityx model) didn't load");
    }
    final sent = {'decision': model, 'state': state};
    final AityxAnswer answer;
    try {
      answer = await _aityx.systemone(sent);
    } on AityxNoKey {
      throw ProposalCheckException(AityxNoKey.message);
    } on AityxUnreachable {
      throw ProposalCheckException(AityxUnreachable.message);
    }
    if (!answer.ok) throw ProposalCheckException(answer.problem!);
    final answers = answer.json;
    if (answers is! Map<String, Object?>) {
      throw ProposalCheckException('unexpected answer from aityx');
    }
    final Map<String, Object?> result;
    try {
      result = toResult(answers, assumedRate);
    } on FormatException {
      throw ProposalCheckException('unexpected answer from aityx');
    }
    // The key is a header, so it's in neither the body nor the answer.
    final key = (await _aityx.connection()).key ?? '';
    try {
      return ProposalCheck.fromJson(
        withAityx(result, sent, answers, answer.text, key),
      );
    } on Error {
      // A verdict or a check result the app doesn't know.
      throw ProposalCheckException('unexpected answer from aityx');
    }
  }
}

class ProposalCheckException implements Exception {
  ProposalCheckException(this.message);
  final String message;
  @override
  String toString() => message;
}
