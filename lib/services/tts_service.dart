import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'audio_player_service.dart';

/// 朗读（TTS）：Android / Windows（SAPI）
/// 状态可见：speaking 驱动按钮图标切换；引擎异常静默降级为"无反馈"而非崩溃。
class TtsService {
  static final TtsService I = TtsService._();

  TtsService._();

  final FlutterTts _tts = FlutterTts();
  bool _inited = false;
  Timer? _speakingTimer;
  Timer? _progressTimer;

  /// 正在朗读（UI 据此切换播放/停止图标）
  final ValueNotifier<bool> speaking = ValueNotifier(false);

  /// 当前（或最近一次）朗读的文本：句卡/朗读按钮据此判断"是不是本条"，
  /// 避免全局进度条让列表里每一行都跟着动
  final ValueNotifier<String> currentText = ValueNotifier('');

  /// 朗读进度估算 0–1（TTS 无真实时间轴，按估算时长线性推进）
  final ValueNotifier<double> progress = ValueNotifier(0);

  /// 展示倍速（1.0 / 1.25 / 1.5 / 2.0 / 0.75）；原生值为 0.5×倍速
  final ValueNotifier<double> rateLabel = ValueNotifier(1.0);
  static const rateOptions = [1.0, 1.25, 1.5, 2.0, 0.75];

  bool get supported =>
      Platform.isAndroid || Platform.isWindows || Platform.isIOS;

  /// TTS 引擎是否可用（初始化失败过就不再重试）
  bool _broken = false;
  bool get available => supported && !_broken;

  Future<void> _init() async {
    if (_inited || _broken) return;
    try {
      await _tts.awaitSpeakCompletion(false);
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5 * rateLabel.value);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      _inited = true;
    } catch (e) {
      _broken = true; // 系统缺英语语音包等：不再重试，UI 显示不可用
    }
  }

  /// 朗读一段文本；返回是否真的发起了朗读（false = 引擎不可用）
  Future<bool> speak(String text) async {
    if (!available || text.trim().isEmpty) return false;
    await _init();
    if (_broken) return false;
    try {
      // 互斥：TTS 开讲前停掉音频，保证同一时刻只有一个在发声
      await AudioPlayerService.I.stop();
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {
      return false;
    }
    speaking.value = true;
    currentText.value = text;
    // 平台完成回调在 Windows 不可用：按 2.5 词/秒估算时长自动复位
    final secs = (text.trim().split(RegExp(r'\s+')).length / 2.5 + 0.6).clamp(
      0.8,
      600.0,
    );
    _speakingTimer?.cancel();
    _progressTimer?.cancel();
    progress.value = 0;
    final totalMs = (secs * 1000).round();
    final startedAt = DateTime.now();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 120), (t) {
      final p = DateTime.now().difference(startedAt).inMilliseconds / totalMs;
      progress.value = p.clamp(0, 1);
      if (p >= 1) t.cancel();
    });
    _speakingTimer = Timer(Duration(milliseconds: totalMs), () {
      _progressTimer?.cancel();
      progress.value = 1;
      if (speaking.value) speaking.value = false;
    });
    return true;
  }

  /// 切换朗读倍速（循环档位：1.0 → 1.25 → 1.5 → 2.0 → 0.75）
  Future<void> cycleRate() async {
    final i = rateOptions.indexOf(rateLabel.value);
    final next = rateOptions[(i < 0 ? 0 : i + 1) % rateOptions.length];
    rateLabel.value = next;
    try {
      await _tts.setSpeechRate(0.5 * next);
    } catch (_) {}
  }

  Future<void> stop() async {
    _speakingTimer?.cancel();
    _progressTimer?.cancel();
    progress.value = 0;
    try {
      await _tts.stop();
    } catch (_) {}
    if (speaking.value) speaking.value = false;
  }

  /// 朗读或停止（按钮行为）。正在读别的内容时直接切换到新文本，
  /// 不用先点一次停止（旧行为：只会停掉当前朗读，得再点一次才开始读新的）
  Future<bool> toggle(String text) async {
    if (speaking.value) {
      if (currentText.value == text) {
        await stop();
        return false;
      }
    }
    return speak(text);
  }
}
