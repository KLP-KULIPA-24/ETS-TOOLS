import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'tts_service.dart';

/// 全局音频播放服务：倍速 / AB 循环 / 区间播放（逐句跟读）
class AudioPlayerService extends ChangeNotifier {
  static final AudioPlayerService I = AudioPlayerService._();

  AudioPlayerService._() {
    _init();
  }

  final player = AudioPlayer();

  // AB 循环
  double? loopA;
  double? loopB;
  Timer? _loopTimer;

  // 区间播放（逐句）：到终点自动暂停，**不循环**——
  // 循环重播是“播完自己跳下一个、又回去重播”的主诉根因
  double? _segTo;
  String currentSource = '';

  bool get playing => player.playing;
  double get speed => player.speed;
  Duration get position => player.position;
  Duration get duration => player.duration ?? Duration.zero;

  void _init() {
    player.playerStateStream.listen((s) {
      notifyListeners();
    });
    player.positionStream.listen((pos) {
      final posSec = pos.inMilliseconds / 1000.0;
      // A-B 显式循环（用户主动设置）
      if (loopA != null && loopB != null && loopB! > loopA!) {
        final end = loopB! + 0.05;
        if (posSec >= end ||
            (player.duration != null && pos >= player.duration!)) {
          player.seek(Duration(milliseconds: (loopA! * 1000).round()));
        }
        return;
      }
      // 区间播放：到终点暂停一次（停在区间结尾，再点同句可重听）
      final to = _segTo;
      if (to != null && to > 0 && pos.inMilliseconds > 0 && posSec >= to) {
        _segTo = null;
        player.pause();
      }
    });
  }

  /// 打开本地文件或 URL
  Future<void> open(
    String source, {
    bool autoPlay = true,
    double? from,
    double? to,
  }) async {
    // 互斥：切源播放前停掉 TTS
    unawaited(TtsService.I.stop());
    if (source == currentSource && player.audioSource != null) {
      await player.seek(Duration(milliseconds: ((from ?? 0) * 1000).round()));
      if (autoPlay) await player.play();
      _segTo = to;
      notifyListeners();
      return;
    }
    await player.stop();
    loopA = null;
    loopB = null;
    _segTo = to;
    currentSource = source;
    final isUrl = source.startsWith('http');
    final src = isUrl
        ? AudioSource.uri(Uri.parse(source))
        : AudioSource.uri(Uri.file(source));
    await player.setAudioSource(src);
    if (from != null && from > 0) {
      await player.seek(Duration(milliseconds: (from * 1000).round()));
    }
    if (autoPlay) await player.play();
    notifyListeners();
  }

  Future<void> play() async {
    // 互斥：音频播放前停掉 TTS
    unawaited(TtsService.I.stop());
    await player.play();
  }

  Future<void> pause() async => player.pause();
  Future<void> toggle() async =>
      player.playing ? player.pause() : player.play();
  Future<void> seek(double seconds) async =>
      player.seek(Duration(milliseconds: (seconds * 1000).round()));
  Future<void> stop() async {
    await player.stop();
    currentSource = '';
    _clearLoop();
    notifyListeners();
  }

  Future<void> setSpeed(double s) async {
    await player.setSpeed(s);
    notifyListeners();
  }

  void setLoop(double? a, double? b) {
    loopA = a;
    loopB = b;
    notifyListeners();
  }

  void _clearLoop() {
    loopA = null;
    loopB = null;
    _segTo = null;
    _loopTimer?.cancel();
  }

  @override
  void dispose() {
    _loopTimer?.cancel();
    player.dispose();
    super.dispose();
  }
}
