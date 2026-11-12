/// The little of AWS Poker Tour needs, in pure Dart: credentials, and
/// Signature Version 4 in its two forms, a presigned URL (the browser's
/// GET of the key object) and signed headers (the server's S3 and Lambda
/// calls). No AWS SDK: a few hundred lines, tested against AWS's own
/// published examples.
library;

export 'src/credentials.dart';
export 'src/sigv4.dart';
