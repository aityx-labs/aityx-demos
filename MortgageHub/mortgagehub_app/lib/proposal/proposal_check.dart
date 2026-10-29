import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'proposal_request.dart';

/// The regulatory check of a proposal request: aityx.ai's verdict under
/// current US rules, through the app's API (mortgagehub_api), which holds
/// the aityx key.
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

  /// The body the API sent to aityx (the model and its inputs; the key is a
  /// header, so not in it), and aityx's answer, as JSON. Null when the API
  /// didn't include them.
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

/// The app's API, at API_BASE_URL: empty means the app's own origin (the
/// dev server proxies /api/ to the API; see scripts/flutter-web.sh).
class ApiProposalChecker implements ProposalChecker {
  ApiProposalChecker({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _baseUrl = baseUrl ?? _defaultBaseUrl;

  static const _defaultBaseUrl = String.fromEnvironment('API_BASE_URL');

  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;

  Uri get _checkUrl => _baseUrl.isEmpty
      ? Uri.base.resolve('/api/proposals/check')
      : Uri.parse('$_baseUrl/api/proposals/check');

  /// Closes the HTTP client it made; a client passed in is the caller's.
  void close() {
    if (_ownsClient) _client.close();
  }

  @override
  Future<ProposalCheck> check(ProposalRequest request) async {
    final response = await _client
        .post(
          _checkUrl,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(request.toJson()),
        )
        .timeout(const Duration(seconds: 90));
    if (response.statusCode != 200) {
      final error = switch (_tryDecode(response.body)) {
        {'error': final String message} => message,
        _ => 'HTTP ${response.statusCode}',
      };
      throw ProposalCheckException(error);
    }
    return ProposalCheck.fromJson(
      jsonDecode(response.body) as Map<String, Object?>,
    );
  }

  static Object? _tryDecode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }
}

class ProposalCheckException implements Exception {
  ProposalCheckException(this.message);
  final String message;
  @override
  String toString() => message;
}
