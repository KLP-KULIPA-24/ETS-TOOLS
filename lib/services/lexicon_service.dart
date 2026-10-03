import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'settings_service.dart';

/// 词典词条（音标 + 发音 + 释义），来自 E听说 内置 pc_xst_dict
class LexEntry {
  final String word;
  final String trans;
  final String phonEn;
  final String phonUs;
  final String audioEn;
  final String audioUs;
  const LexEntry({
    required this.word,
    required this.trans,
    required this.phonEn,
    required this.phonUs,
    required this.audioEn,
    required this.audioUs,
  });
}

/// 极简词典：单词 → 音标/发音（供单词详情与单词本使用）
class LexiconService extends ChangeNotifier {
  static final LexiconService I = LexiconService._();

  LexiconService._();

  Map<String, LexEntry> _map = {};
  bool loading = false;

  bool get loaded => _map.isNotEmpty;

  Future<void> ensureLoaded() async {
    if (_map.isNotEmpty || loading) return;
    loading = true;
    try {
      // 数据目录（含提取后的副本）
      for (final root in SettingsService.I.activeRoots) {
        final f = File(p.join(root, 'pc_xst_dict', 'pc_xst_dict.json'));
        if (f.existsSync()) {
          _map = await compute(_parse, f.path);
          break;
        }
      }
      if (_map.isEmpty) {
        // 兜底：应用文档目录（Windows 便携版可能无 ETS 目录）
        final docs = await getApplicationDocumentsDirectory();
        final f = File(p.join(docs.path, 'pc_xst_dict', 'pc_xst_dict.json'));
        if (f.existsSync()) _map = await compute(_parse, f.path);
      }
    } catch (_) {}
    loading = false;
    notifyListeners();
  }

  static Map<String, LexEntry> _parse(String path) {
    final out = <String, LexEntry>{};
    try {
      final list = const JsonDecoder().convert(
        File(path).readAsStringSync().replaceFirst('\ufeff', ''),
      );
      for (final e in (list as List).whereType<Map>()) {
        final w = '${e['Word'] ?? ''}'.toLowerCase();
        if (w.isEmpty) continue;
        out[w] = LexEntry(
          word: '${e['Word']}',
          trans: '${e['Trans'] ?? ''}',
          phonEn: '${e['Spell_EN'] ?? ''}',
          phonUs: '${e['Spell_US'] ?? ''}',
          audioEn: '${e['AudioUrl_EN'] ?? ''}',
          audioUs: '${e['AudioUrl_US'] ?? ''}',
        );
      }
    } catch (_) {}
    return out;
  }

  LexEntry? lookup(String word) {
    if (word.isEmpty) return null;
    return _map[word.trim().toLowerCase()];
  }
}
