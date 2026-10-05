import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_service.dart';

/// 单词释义：**调 AI 生成**，结果**本地缓存**。
///
/// 为什么不用内置词典当主来源：E听说 自带的 `pc_xst_dict` 只有音标和录音，
/// 释义字段经常是空的（弹层直接显示"内置词典暂未收录这个词"）。
/// 既然 App 本来就能调 AI，释义就交给 AI 生成——覆盖率高得多，
/// 而且能给出词性、例句这类词典不会给的东西。
/// 内置词典降级为辅助：它仍然负责**音标和真人发音**，那是即时且免费的。
///
/// 缓存：同一批作业里同一个词会被反复点，每次都调 AI 既慢又烧额度，
/// 释义对单��来说也不会变——查一次存下来，之后直接命中。
class WordGlossService {
  static final WordGlossService I = WordGlossService._();

  WordGlossService._();

  static const _kPrefix = 'word_gloss_';
  static const _kIndex = 'word_gloss_index';

  /// 缓存索引（单词 -> 是否有缓存），避免每次都枚举所有 SharedPreferences key
  final ValueNotifier<int> cachedCount = ValueNotifier(0);

  SharedPreferences? _sp;
  final Map<String, String> _memo = {};

  Future<SharedPreferences> _prefs() async =>
      _sp ??= await SharedPreferences.getInstance();

  Future<void> init() async {
    final sp = await _prefs();
    final idx = sp.getStringList(_kIndex) ?? const <String>[];
    for (final w in idx) {
      final v = sp.getString('$_kPrefix$w');
      if (v != null) _memo[w] = v;
    }
    cachedCount.value = _memo.length;
  }

  String? peek(String word) => _memo[word.toLowerCase()];

  Future<void> _put(String word, String text) async {
    final w = word.toLowerCase();
    _memo[w] = text;
    cachedCount.value = _memo.length;
    final sp = await _prefs();
    await sp.setString('$_kPrefix$w', text);
    final idx = sp.getStringList(_kIndex) ?? <String>[];
    if (!idx.contains(w)) {
      idx.add(w);
      await sp.setStringList(_kIndex, idx);
    }
  }

  /// 释义一个词。命中缓存直接返回；否则调 AI 生成后写缓存。
  /// 返回 null 表示没生成成（无模型 / 断网），由调用方决定怎么提示。
  Future<String?> gloss(String raw) async {
    final word = raw.trim().split(RegExp(r'\s+')).first;
    if (word.isEmpty) return null;

    await init();
    final hit = _memo[word.toLowerCase()];
    if (hit != null && hit.isNotEmpty) return hit;

    final (text, _) = await AiService.I.chatWithFailover(
      temperature: 0.2,
      maxTokens: 400,
      messages: [
        {
          'role': 'system',
          'content':
              '你是英语词典。只回答这个单词本身，不要展开讲别的。'
              '严格按下面格式输出，不要加任何额外说明或 Markdown 标题：\n'
              '音标：/英式音标/  /美式音标/\n'
              '释义：1. 词性. 中文释义  2. 词性. 中文释义（最多 3 条，按义项频次排）\n'
              '例句：一句英文例句 + 中文翻译',
        },
        {'role': 'user', 'content': word},
      ],
    );

    final out = text.trim();
    if (out.isEmpty) return null;
    await _put(word, out);
    return out;
  }

  /// 把 AI 返回的多行文本拆成 音标 / 释义 / 例句 三段，方便排版
  static ({String phon, String def, String example}) splitGloss(String raw) {
    String phon = '', def = '', example = '';
    for (final line in const LineSplitter().convert(raw)) {
      final t = line.trim();
      if (t.isEmpty) continue;
      if (t.startsWith('音标')) {
        phon = t.replaceFirst('音标', '').replaceAll('：', '').trim();
      } else if (t.startsWith('例句')) {
        example = t.replaceFirst('例句', '').replaceAll('：', '').trim();
      } else if (t.startsWith('释义')) {
        def = t.replaceFirst('释义', '').replaceAll('：', '').trim();
      } else if (def.isNotEmpty) {
        def = '$def\n$t';
      } else {
        def = t;
      }
    }
    return (phon: phon, def: def, example: example);
  }
}
