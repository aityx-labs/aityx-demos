/// Recording the admissions the feed reads (lib/simulation.dart's
/// PeopleFeed) into the database's admissions table (lib/db.dart). The
/// feed's poll loop must never wait on the database, so each admission is
/// queued here and written in the background, in arrival order, and a
/// failed write is retried after a pause rather than dropped, unless the
/// database refused that admission itself: a retry would fail the same
/// way forever and hold up every admission behind it.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:io';

class AdmissionRecorder {
  /// [insert] writes one admission, idempotently by its event id: true
  /// when it inserted it, false when that event id was already recorded;
  /// it throws when it can't. [isPermanent] tells an error that a retry
  /// can't fix (bad data: lib/db.dart's isPermanentError) from one that
  /// passes (the database down).
  AdmissionRecorder(
    this._insert, {
    this.retryAfter = const Duration(seconds: 3),
    this.limit = 10000,
    bool Function(Object error)? isPermanent,
  }) : _isPermanent = isPermanent ?? _never;

  final Future<bool> Function(Map<String, Object?> admission) _insert;
  final bool Function(Object error) _isPermanent;
  final Duration retryAfter;

  /// How many admissions may wait for a database that stays down; beyond
  /// that the oldest are dropped, and each drop is logged.
  final int limit;

  final _queue = ListQueue<Map<String, Object?>>();
  Completer<void>? _draining;
  bool _stopped = false;

  /// How many admissions wait to be written.
  int get pending => _queue.length;

  /// Queues [admission] to be written; returns at once.
  void record(Map<String, Object?> admission) {
    if (_stopped) return;
    _queue.addLast(admission);
    if (_queue.length > limit) {
      stderr.writeln('admissions: dropped ${_queue.removeFirst()['eventId']}, too many waiting for the database');
    }
    if (_draining == null) unawaited(_drain());
  }

  /// Completes once every queued admission has been written.
  Future<void> get idle => _draining?.future ?? Future<void>.value();

  Future<void> _drain() async {
    final draining = _draining = Completer<void>();
    var failures = 0;
    while (_queue.isNotEmpty && !_stopped) {
      final admission = _queue.first;
      try {
        final inserted = await _insert(admission);
        if (_queue.isNotEmpty && identical(_queue.first, admission)) _queue.removeFirst();
        // A replay, or two APIs on one Kafka: worth knowing, not an error.
        if (!inserted) stdout.writeln('admissions: ${admission['eventId']} already recorded, skipped');
        if (failures > 0) stdout.writeln('admissions: recording again after $failures failures');
        failures = 0;
      } catch (error) {
        if (_isPermanent(error)) {
          if (_queue.isNotEmpty && identical(_queue.first, admission)) _queue.removeFirst();
          stderr.writeln('admissions: dropped ${admission['eventId']}, the database refused it: $error');
          continue;
        }
        // Logged at the first failure and every tenth after, as the
        // database may stay down a while.
        if (failures++ % 10 == 0) {
          stderr.writeln(
            'admissions: recording ${admission['eventId']} failed, '
            '${_queue.length} waiting, retrying: $error',
          );
        }
        await Future<void>.delayed(retryAfter);
      }
    }
    _draining = null;
    draining.complete();
  }

  /// Stops writing; logs the admissions still waiting, which are lost.
  void stop() {
    _stopped = true;
    if (_queue.isNotEmpty) stderr.writeln('admissions: stopping with ${_queue.length} not recorded');
  }
}

bool _never(Object error) => false;
