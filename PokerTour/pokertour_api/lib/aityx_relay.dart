/// The local server's relay to aityx, for the browser: aityx staging
/// takes no calls from browsers (its CORS preflight answers 403, whatever
/// the origin), so on a laptop the app sends its decisions to
/// `/aityx/v1/systemone` on its own origin, and this forwards them to the
/// server's AITYX_URL with the browser's own Authorization header: the
/// player's key, or the tour's they fetched. It never adds a key of its
/// own, never logs the header, and relays nothing but systemone. Deployed,
/// the app calls aityx production directly (it allows browsers), and
/// there is no relay.
library;

import 'dart:async';

import 'package:http/http.dart' as http;

/// What aityx answered, to send back as it is.
class Relayed {
  const Relayed(this.status, this.body, {this.contentType = 'application/json'});

  final int status;
  final List<int> body;
  final String contentType;
}

class AityxRelay {
  AityxRelay(this.base, {http.Client? client, this.timeout = const Duration(seconds: 90)})
    : _client = client ?? http.Client();

  /// aityx's base URL (the server's AITYX_URL).
  final Uri base;
  final http.Client _client;
  final Duration timeout;

  /// The largest body relayed: a decision is a few kilobytes.
  static const maxBody = 256 * 1024;

  Uri get target => Uri.parse('${base.toString().replaceAll(RegExp(r'/+$'), '')}/v1/systemone');

  /// Forwards [body] with [authorization] (the browser's header, passed
  /// on as it is) to aityx's systemone.
  Future<Relayed> systemone(List<int> body, {String? authorization}) async {
    if (authorization == null || !authorization.startsWith('Bearer ') || authorization.length < 12) {
      return _problem(401, 'unauthorized', 'no aityx key: set yours in Profile');
    }
    if (body.length > maxBody) return _problem(413, 'too_large', 'request too large');
    try {
      final answer = await _client
          .post(target, headers: {'Content-Type': 'application/json', 'Authorization': authorization}, body: body)
          .timeout(timeout);
      return Relayed(answer.statusCode, answer.bodyBytes, contentType: answer.headers['content-type'] ?? 'application/json');
    } on TimeoutException {
      return _problem(504, 'relay_timeout', 'aityx did not answer the relay in ${timeout.inSeconds} s');
    } catch (error) {
      return _problem(502, 'relay_unreachable', 'aityx could not be reached from the server (${error.runtimeType})');
    }
  }

  static Relayed _problem(int status, String code, String detail) =>
      Relayed(status, '{"code":"$code","detail":"$detail"}'.codeUnits, contentType: 'application/problem+json');

  void close() => _client.close();
}
