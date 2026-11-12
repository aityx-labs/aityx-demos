import 'dart:math';

import 'package:aityx_web/aityx_web.dart' show StorageArea;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokertour_app/music/music_control.dart';
import 'package:pokertour_app/music/soundtrack.dart';
import 'package:pokertour_app/persist/storage_area.dart';

/// Remembers what it was asked to play, and ends a track when told.
class FakePlayer implements TrackPlayer {
  final played = <String>[];
  double? volume;
  bool paused = false;
  VoidCallback? _ended;

  void end() => _ended?.call();

  @override
  void play(String asset, double volume, {required VoidCallback onEnded}) {
    played.add(asset);
    this.volume = volume;
    paused = false;
    _ended = onEnded;
  }

  @override
  void setVolume(double volume) => this.volume = volume;

  @override
  void pause() => paused = true;

  @override
  void resume() => paused = false;

  @override
  void dispose() {}
}

/// Storage the browser blocks: every read and write throws.
class BlockedArea implements StorageArea {
  @override
  String? read(String name) => throw StateError('storage blocked');

  @override
  void write(String name, String value) => throw StateError('storage blocked');

  @override
  void remove(String name) => throw StateError('storage blocked');
}

void main() {
  test('the five tracks play in a random order, round and round, never one twice in a row', () {
    final player = FakePlayer();
    final music = Soundtrack(storage: memoryArea(), player: player, random: Random(3));
    music.start();
    music.start(); // once
    for (var i = 0; i < 49; i++) {
      player.end();
    }
    expect(player.played, hasLength(50));
    for (var round = 0; round < 10; round++) {
      expect(player.played.sublist(round * 5, round * 5 + 5).toSet(), Soundtrack.tracks.toSet());
    }
    for (var i = 1; i < player.played.length; i++) {
      expect(player.played[i], isNot(player.played[i - 1]));
    }
    // Not always the same order.
    expect(player.played.sublist(0, 5), isNot(player.played.sublist(5, 10)));
    expect(player.volume, Soundtrack.defaultVolume);
  });

  test('the volume and the mute are remembered', () {
    final storage = memoryArea();
    final player = FakePlayer();
    final music = Soundtrack(storage: storage, player: player)..start();
    music.setVolume(0.6);
    music.toggleMute();
    expect(player.volume, 0.6);
    expect(player.paused, isTrue);

    final again = FakePlayer();
    final next = Soundtrack(storage: storage, player: again)..start();
    expect(next.volume, 0.6);
    expect(next.muted, isTrue);
    expect(again.played, isEmpty); // muted: silence until unmuted
    next.toggleMute();
    expect(again.played, hasLength(1));
    expect(again.volume, 0.6);
  });

  test('blocked storage: the defaults, and settings that last the visit', () {
    final player = FakePlayer();
    final music = Soundtrack(storage: BlockedArea(), player: player)..start();
    expect(music.volume, Soundtrack.defaultVolume);
    expect(music.muted, isFalse);
    expect(player.played, hasLength(1));
    music.setVolume(0.5);
    music.toggleMute();
    expect(music.volume, 0.5);
    expect(music.muted, isTrue);
  });

  test('stop silences it until the next start', () {
    final player = FakePlayer();
    final music = Soundtrack(storage: memoryArea(), player: player)..start();
    music.stop();
    expect(player.paused, isTrue);
    expect(music.current, isNull);
    music.start();
    expect(player.played, hasLength(2));
    expect(player.paused, isFalse);
  });

  testWidgets('the controls mute and set the volume', (tester) async {
    tester.view.physicalSize = const Size(1200, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final player = FakePlayer();
    final music = Soundtrack(storage: memoryArea(), player: player)..start();
    await tester.pumpWidget(MaterialApp(home: Scaffold(appBar: AppBar(actions: [MusicControl(soundtrack: music)]))));

    await tester.drag(find.byKey(const Key('music-volume')), const Offset(60, 0));
    await tester.pump();
    expect(music.volume, greaterThan(Soundtrack.defaultVolume));
    expect(player.volume, music.volume);

    await tester.tap(find.byKey(const Key('music-mute')));
    await tester.pump();
    expect(music.muted, isTrue);
    expect(player.paused, isTrue);
    expect(find.byIcon(Icons.music_off_outlined), findsOneWidget);
  });
}
