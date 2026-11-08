/// Where the tour's files live: leaderboard.json (the entries, the
/// records, the history) and live.json (the tournament being played, the
/// runner's state). A folder on the laptop and in the container; an S3
/// bucket on AWS, where the API and the runner are separate Lambda
/// functions and only the bucket is shared. Every write can be made
/// conditional on the version read, so two writers never lose each
/// other's change: the one that loses the race reads again and redoes
/// its change (Boards.update, lib/leaderboard.dart).
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'aws/s3.dart';

/// A file's text and its version (a hash, or S3's ETag).
class Stored {
  const Stored(this.text, this.version);

  final String text;
  final String version;
}

/// A conditional write found another version in place.
class StoreConflict implements Exception {
  const StoreConflict(this.name);

  final String name;

  @override
  String toString() => '$name was changed by someone else';
}

abstract interface class Store {
  /// [name]'s text and version; null when there is no such file.
  Future<Stored?> read(String name);

  /// Writes [text] as [name] and gives the new version. With
  /// [ifVersion], only when the version in place is that one, or, when it
  /// is the empty string, only when there is no file yet: a
  /// [StoreConflict] otherwise. Without it, unconditionally.
  Future<String> write(String name, String text, {String? ifVersion});

  Future<void> delete(String name);
}

/// The version of a text, for the stores that have no ETag.
String versionOf(String text) => sha256.convert(utf8.encode(text)).toString().substring(0, 16);

/// In memory: for tests.
class MemoryStore implements Store {
  final _files = <String, Stored>{};

  @override
  Future<Stored?> read(String name) async => _files[name];

  @override
  Future<String> write(String name, String text, {String? ifVersion}) async {
    final current = _files[name]?.version ?? '';
    if (ifVersion != null && ifVersion != current) throw StoreConflict(name);
    final version = versionOf(text);
    _files[name] = Stored(text, version);
    return version;
  }

  @override
  Future<void> delete(String name) async => _files.remove(name);
}

/// A folder (POKERTOUR_DATA): one process writes it, through a temporary
/// file, so a crash leaves the old file whole.
class FileStore implements Store {
  FileStore(this.dir);

  final Directory dir;

  File _file(String name) => File('${dir.path}/$name');

  @override
  Future<Stored?> read(String name) async {
    final f = _file(name);
    if (!await f.exists()) return null;
    final text = await f.readAsString();
    return Stored(text, versionOf(text));
  }

  @override
  Future<String> write(String name, String text, {String? ifVersion}) async {
    if (ifVersion != null) {
      final current = (await read(name))?.version ?? '';
      if (current != ifVersion) throw StoreConflict(name);
    }
    final f = _file(name);
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(text);
    await tmp.rename(f.path);
    return versionOf(text);
  }

  @override
  Future<void> delete(String name) async {
    final f = _file(name);
    if (await f.exists()) await f.delete();
  }
}

/// An S3 bucket, under [prefix]: the version is the object's ETag, and
/// the conditional writes are S3's own (If-Match, If-None-Match), so two
/// Lambda functions can share it.
class S3Store implements Store {
  S3Store(this.s3, this.bucket, {this.prefix = ''});

  final S3Client s3;
  final String bucket;
  final String prefix;

  @override
  Future<Stored?> read(String name) async {
    final object = await s3.get(bucket, '$prefix$name');
    if (object == null) return null;
    return Stored(object.text, object.etag);
  }

  @override
  Future<String> write(String name, String text, {String? ifVersion}) async {
    try {
      return await s3.put(
        bucket,
        '$prefix$name',
        utf8.encode(text),
        contentType: 'application/json',
        ifMatch: ifVersion == null || ifVersion.isEmpty ? null : ifVersion,
        ifNoneMatch: ifVersion != null && ifVersion.isEmpty,
      );
    } on S3Conflict {
      throw StoreConflict(name);
    }
  }

  @override
  Future<void> delete(String name) => s3.delete(bucket, '$prefix$name');
}
