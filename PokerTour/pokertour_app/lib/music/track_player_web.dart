/// The browser: one audio element. A browser may refuse to play before
/// the user has touched the page (a reload, already signed in): then the
/// music waits for the first click or key.
library;

import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'soundtrack.dart';

TrackPlayer trackPlayer() => _AudioPlayer();

class _AudioPlayer implements TrackPlayer {
  final web.HTMLAudioElement _audio = web.HTMLAudioElement()..preload = 'auto';
  VoidCallback? _onEnded;
  JSFunction? _unlock;
  bool _paused = false;

  _AudioPlayer() {
    _audio.addEventListener('ended', ((web.Event _) => _onEnded?.call()).toJS);
  }

  @override
  void play(String asset, double volume, {required VoidCallback onEnded}) {
    _onEnded = onEnded;
    _paused = false;
    _audio
      ..src = ui_web.assetManager.getAssetUrl(asset)
      ..volume = volume;
    _start();
  }

  void _start() {
    _audio.play().toDart.catchError((Object _) {
      // Not allowed yet: once the user clicks or types.
      _waitForGesture();
      return null;
    });
  }

  void _waitForGesture() {
    if (_unlock != null) return;
    final unlock = ((web.Event _) {
      _stopWaiting();
      if (!_paused) _start();
    }).toJS;
    _unlock = unlock;
    web.document.addEventListener('pointerdown', unlock);
    web.document.addEventListener('keydown', unlock);
  }

  void _stopWaiting() {
    final unlock = _unlock;
    if (unlock == null) return;
    web.document.removeEventListener('pointerdown', unlock);
    web.document.removeEventListener('keydown', unlock);
    _unlock = null;
  }

  @override
  void setVolume(double volume) => _audio.volume = volume;

  @override
  void pause() {
    _paused = true;
    _audio.pause();
  }

  @override
  void resume() {
    _paused = false;
    if (_audio.src.isNotEmpty) _start();
  }

  @override
  void dispose() {
    _stopWaiting();
    _onEnded = null;
    _audio
      ..pause()
      ..removeAttribute('src');
  }
}
