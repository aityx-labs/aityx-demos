import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pokertour_api/aityx_relay.dart';
import 'package:test/test.dart';

void main() {
  test('forwards the browser\'s key and body to systemone, and the answer back', () async {
    late http.Request seen;
    final relay = AityxRelay(
      Uri.parse('https://api-stage.aityx.ai/'),
      client: MockClient((request) async {
        seen = request;
        return http.Response('{"answers":{}}', 200, headers: {'content-type': 'application/json'});
      }),
    );
    final answer = await relay.systemone('{"state":1}'.codeUnits, authorization: 'Bearer player-key');
    expect(seen.url.toString(), 'https://api-stage.aityx.ai/v1/systemone');
    expect(seen.headers['Authorization'], 'Bearer player-key');
    expect(seen.body, '{"state":1}');
    expect(answer.status, 200);
    expect(String.fromCharCodes(answer.body), '{"answers":{}}');
  });

  test('no key, no call: the server never adds one', () async {
    var calls = 0;
    final relay = AityxRelay(Uri.parse('https://api-stage.aityx.ai'), client: MockClient((_) async {
      calls++;
      return http.Response('{}', 200);
    }));
    expect((await relay.systemone('{}'.codeUnits)).status, 401);
    expect((await relay.systemone('{}'.codeUnits, authorization: 'Basic x')).status, 401);
    expect(calls, 0);
    expect((await relay.systemone(List.filled(AityxRelay.maxBody + 1, 32), authorization: 'Bearer player-key')).status, 413);
  });

  test('aityx\'s refusals pass through; no answer is a 502', () async {
    final relay = AityxRelay(Uri.parse('https://api-stage.aityx.ai'), client: MockClient((request) async {
      if (request.headers['Authorization'] == 'Bearer bad') return http.Response('{"code":"unauthorized"}', 401);
      throw http.ClientException('down');
    }));
    expect((await relay.systemone('{}'.codeUnits, authorization: 'Bearer bad')).status, 401);
    expect((await relay.systemone('{}'.codeUnits, authorization: 'Bearer good-key')).status, 502);
  });
}
