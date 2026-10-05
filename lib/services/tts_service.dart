import 'dart:async';
import 'dart:io';

import 'package:edge_tts/edge_tts.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'audio_player_service.dart';
import 'settings_service.dart';

/// 朗读（TTS）：**微软 Edge 在线神经语音**（edge_tts 包），双端一致。
///
/// 为什么不用系统 TTS：Android/Windows 的系统语音包常常没装英语，
/// `flutter_tts` 的语言检测直接失败 → 按钮点了没反应。
/// Edge TTS 走微软的在线服务，不需要 API Key、不依赖本机语音包。
///
/// 为什么不用全局 AudioPlayerService：朗读是"临时短音频"，
/// 不该出现在全局迷你播放条里，也不该被 AB 循环那套逻辑牵扯。
/// 这里自带一个独立播放器，只与全局播放器互斥。
class TtsService {
  static final TtsService I = TtsService._();

  TtsService._() {
    _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        // 播完：进度停在末尾，图标切回"朗读"
        progress.value = 1;
        if (speaking.value) speaking.value = false;
        currentText.value = '';
      }
    });
    _player.positionStream.listen(_onPosition);
  }

  final AudioPlayer _player = AudioPlayer();

  /// 正在朗读（UI 据此切换播放/停止图标）
  final ValueNotifier<bool> speaking = ValueNotifier(false);

  /// 当前（或最近一次）朗读的文本：句卡/朗读按钮据此判断"是不是本条"，
  /// 避免全局进度条让列表里每一行都跟着动
  final ValueNotifier<String> currentText = ValueNotifier('');

  /// 朗读进度 0–1，来自播放器的真实 position/duration（不再是按时长估算）
  final ValueNotifier<double> progress = ValueNotifier(0);

  /// 展示倍速（1.0 / 1.25 / 1.5 / 2.0 / 0.75）；作用于播放器，不重新合成
  final ValueNotifier<double> rateLabel = ValueNotifier(1.0);
  static const rateOptions = [1.0, 1.25, 1.5, 2.0, 0.75];

  /// 两个音色（微软 Edge 神经语音，无需 API Key）
  static const voices = <({String id, String name, String hint})>[
    (id: 'en-US-AriaNeural', name: 'Aria', hint: '女声 · 自然'),
    (id: 'en-US-GuyNeural', name: 'Guy', hint: '男声 · 稳重'),
  ];

  static String voiceIdOf(int index) =>
      voices[index.clamp(0, voices.length - 1)].id;

  /// 合成失败（如断网）置位：UI 不再假装"可用"，避免点了没反应又不给解释
  bool _failed = false;
  bool get available => !_failed;

  /// 各平台都支持（Edge TTS 是在线服务，只看有没有网，不看本机语音包）。
  /// 保留这个 getter 是给"选中文字→朗读"这类入口做条件展示用的。
  bool get supported => true;

  /// 最近一次失败原因，供 UI 提示
  final ValueNotifier<String> lastError = ValueNotifier('');

  /// 合成出的临时文件，下次朗读/停止时清掉
  File? _tmp;
  bool _busy = false;

  void _onPosition(Duration pos) {
    final dur = _player.duration;
    if (dur == null || dur.inMilliseconds <= 0) return;
    progress.value = (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
  }

  /// 朗读一段文本；返回是否真的发起了朗读（false = 合成失败）
  Future<bool> speak(String text) async {
    final t = text.trim();
    if (t.isEmpty || _busy) return false;
    _busy = true;
    _failed = false;
    lastError.value = '';
    try {
      // 互斥：同一时刻只允许一个在发声
      await AudioPlayerService.I.stop();
      await _player.stop();
      speaking.value = false;
      progress.value = 0;

      // 先合成完整音频再播：Edge TTS 是流式返回的，边生成边播虽然起步快，
      // 但 MP3 时长要等解析完才知道——进度条又变回"估算"。
      // 句子级朗读只差几百毫秒，换一条真实的进度条更划算。
      final file = await _synthesize(t, _rateArg(rateLabel.value));

      speaking.value = true;
      currentText.value = text;
      await _player.setAudioSource(AudioSource.file(file.path));
      await _player.setSpeed(rateLabel.value);
      await _player.play();
      return true;
    } catch (e) {
      _failed = true;
      lastError.value = '朗读失败：$e';
      progress.value = 0;
      if (speaking.value) speaking.value = false;
      currentText.value = '';
      return false;
    } finally {
      _busy = false;
    }
  }

  /// edge_tts 的 rate 字符串格式：`+20%` / `-10%` / `+0%`
  String _rateArg(double rate) {
    final pct = ((rate - 1) * 100).round();
    return '${pct >= 0 ? '+' : ''}$pct%';
  }

  Future<File> _synthesize(String text, String rate) async {
    final dir = await getTemporaryDirectory();
    final out = File(
      '${dir.path}/tts_${DateTime.now().microsecondsSinceEpoch}.mp3',
    );
    final voice = voiceIdOf(SettingsService.I.ttsVoiceIndex);
    final tts = Communicate(text: text, voice: voice, rate: rate);
    await tts.save(out.path);
    final old = _tmp;
    _tmp = out;
    if (old != null) {
      try {
        await old.delete();
      } catch (_) {}
    }
    return out;
  }

  /// 切换朗读倍速（循环档位：1.0 → 1.25 → 1.5 → 2.0 → 0.75）
  /// 直接调播放器速度，不用重新合成
  Future<void> cycleRate() async {
    final i = rateOptions.indexOf(rateLabel.value);
    rateLabel.value = rateOptions[(i < 0 ? 0 : i + 1) % rateOptions.length];
    try {
      await _player.setSpeed(rateLabel.value);
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
    progress.value = 0;
    if (speaking.value) speaking.value = false;
  }

  /// 朗读或停止（按钮行为）。正在读别的内容时直接切换到新文本，
  /// 不用先点一次停止（旧行为：只会停掉当前朗读，得再点一次才开始读新的）
  Future<bool> toggle(String text) async {
    if (speaking.value && currentText.value == text) {
      await stop();
      return false;
    }
    return speak(text);
  }
}
