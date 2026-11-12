/// The Lambda runtime API, as a custom runtime: the executable is
/// `bootstrap`, polls the runtime for the next invocation, runs the
/// handler, and posts its result (or its error) back, for ever. The
/// little the functions need of it (https://docs.aws.amazon.com/lambda/latest/dg/runtimes-api.html).
library;

import 'dart:convert';
import 'dart:io';

/// What the runtime says of the invocation: its id and when it must be
/// over.
class LambdaContext {
  const LambdaContext({required this.requestId, required this.deadline});

  final String requestId;
  final DateTime deadline;

  Duration remaining([DateTime? now]) => deadline.difference(now ?? DateTime.now());
}

/// Handles one invocation: the event, as JSON, to the result, as JSON.
typedef LambdaHandler = Future<Object?> Function(Object? event, LambdaContext context);

/// Serves invocations with [handler] until the runtime is torn down.
Future<Never> runLambda(LambdaHandler handler) async {
  final api = Platform.environment['AWS_LAMBDA_RUNTIME_API'];
  if (api == null || api.isEmpty) {
    stderr.writeln('error: AWS_LAMBDA_RUNTIME_API is not set: this is not a Lambda function');
    exit(1);
  }
  final base = 'http://$api/2018-06-01/runtime';
  final client = HttpClient();
  while (true) {
    final next = await (await client.getUrl(Uri.parse('$base/invocation/next'))).close();
    final id = next.headers.value('lambda-runtime-aws-request-id') ?? '';
    final deadlineMs = int.tryParse(next.headers.value('lambda-runtime-deadline-ms') ?? '') ?? 0;
    final text = await utf8.decoder.bind(next).join();
    Object? event;
    try {
      event = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      event = text;
    }
    final context = LambdaContext(
      requestId: id,
      deadline: deadlineMs == 0 ? DateTime.now().add(const Duration(seconds: 3)) : DateTime.fromMillisecondsSinceEpoch(deadlineMs),
    );
    String path;
    Object payload;
    try {
      payload = await handler(event, context) ?? const <String, Object?>{};
      path = '$base/invocation/$id/response';
    } catch (error, stack) {
      stderr.writeln('lambda: $error\n$stack');
      payload = {'errorMessage': '$error', 'errorType': '${error.runtimeType}'};
      path = '$base/invocation/$id/error';
    }
    final post = await client.postUrl(Uri.parse(path));
    post.headers.contentType = ContentType.json;
    post.write(jsonEncode(payload));
    await (await post.close()).drain<void>();
  }
}
