import 'package:aws_lite/aws_lite.dart';
import 'package:test/test.dart';

/// The credentials of the S3 developer guide's examples.
final example = AwsCredentials(
  accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
  secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
);

void main() {
  test('the presigned GET of the S3 documentation', () {
    // "Example: GET object using a presigned URL", in "Authenticating
    // Requests: Using Query Parameters".
    final url = presignGet(
      credentials: example,
      region: 'us-east-1',
      host: 'examplebucket.s3.amazonaws.com',
      path: '/test.txt',
      now: DateTime.utc(2013, 5, 24),
      expires: 86400,
    );
    expect(url.queryParameters['X-Amz-Signature'], 'aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404');
    expect(url.queryParameters['X-Amz-SignedHeaders'], 'host');
  });

  test('the signed GET of the S3 documentation', () {
    // "Example: GET Object", in "Authenticating Requests: Using the
    // Authorization Header (Transferring Payload in a Single Chunk)".
    final signed = signRequest(
      credentials: example,
      region: 'us-east-1',
      service: 's3',
      method: 'GET',
      uri: Uri.parse('https://examplebucket.s3.amazonaws.com/test.txt'),
      headers: {'Range': 'bytes=0-9'},
      now: DateTime.utc(2013, 5, 24),
    );
    expect(signed.headers['x-amz-content-sha256'], 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    expect(signed.headers['x-amz-date'], '20130524T000000Z');
    expect(
      signed.headers['authorization'],
      'AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, '
      'SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, '
      'Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41',
    );
    expect(signed.headers.containsKey('host'), isFalse, reason: 'the client sets it');
  });

  test('a session token is signed too, and the path is encoded once', () {
    final signed = signRequest(
      credentials: const AwsCredentials(accessKeyId: 'ASIA', secretAccessKey: 's', sessionToken: 'tok=='),
      region: 'eu-west-1',
      service: 's3',
      method: 'PUT',
      uri: Uri(scheme: 'https', host: 'b.s3.eu-west-1.amazonaws.com', pathSegments: ['poker tour', 'live.json']),
      headers: {'Content-Type': 'application/json', 'If-Match': '"abc"'},
      body: '{"a":1}'.codeUnits,
    );
    expect(signed.uri.toString(), 'https://b.s3.eu-west-1.amazonaws.com/poker%20tour/live.json');
    expect(signed.headers['x-amz-security-token'], 'tok==');
    expect(signed.headers['authorization'], contains('SignedHeaders=content-type;host;if-match;x-amz-content-sha256;x-amz-date;x-amz-security-token,'));
  });

  test('credentials from a function\'s environment', () {
    expect(AwsCredentials.fromEnvironment(const {}), isNull);
    final c = AwsCredentials.fromEnvironment(const {'AWS_ACCESS_KEY_ID': 'A', 'AWS_SECRET_ACCESS_KEY': 'S', 'AWS_SESSION_TOKEN': 'T'});
    expect(c?.sessionToken, 'T');
    expect(c.toString(), isNot(contains('S')), reason: 'never the secret');
  });
}
