/// AWS credentials: temporary ones from STS (the browser's, for the key
/// object), or a Lambda function's own, from its environment.
class AwsCredentials {
  const AwsCredentials({
    required this.accessKeyId,
    required this.secretAccessKey,
    this.sessionToken = '',
    this.expiration,
  });

  /// A Lambda function's credentials: AWS_ACCESS_KEY_ID,
  /// AWS_SECRET_ACCESS_KEY and AWS_SESSION_TOKEN; null when unset.
  static AwsCredentials? fromEnvironment(Map<String, String> env) {
    final id = env['AWS_ACCESS_KEY_ID'] ?? '';
    final secret = env['AWS_SECRET_ACCESS_KEY'] ?? '';
    if (id.isEmpty || secret.isEmpty) return null;
    return AwsCredentials(accessKeyId: id, secretAccessKey: secret, sessionToken: env['AWS_SESSION_TOKEN'] ?? '');
  }

  final String accessKeyId;
  final String secretAccessKey;

  /// Empty for long-term credentials (AWS's own examples); STS's and a
  /// Lambda function's are temporary and carry one.
  final String sessionToken;

  /// When they stop working; null when unknown.
  final DateTime? expiration;

  /// For debugging: never shows the secret or the token.
  @override
  String toString() => 'AwsCredentials($accessKeyId${expiration == null ? '' : ', until $expiration'})';
}
