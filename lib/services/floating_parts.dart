/// 悬浮窗的分段内容构造：把一份套题（Part A/B/C 各一个 content_*）压成
/// "标签 + 正文" 列表，交给原生悬浮窗渲染成一排可点的 A/B/C 按钮。
///
/// 各题型取什么（用户指定）：
/// - 模仿朗读：朗读原文
/// - 角色扮演：三问中「你要问的英文问题」+ 五答里最短的参考答案
/// - 故事复述：标准复述范文里最短的一篇（范文1）
library;

import '../models/ets_models.dart';

class FloatingPart {
  final String label; // A / B / C
  final String text;
  const FloatingPart(this.label, this.text);
}

/// HTML 标签清洗：E听说 正文里带 </br> 之类，直接展示会露出标签
String _clean(String s) => s
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

/// 最短的一段（用户：角色扮演取最短参考答案 / 故事复述取最短范文）
String _shortest(List<String> list) {
  final items = list.where((e) => e.trim().isNotEmpty).toList();
  if (items.isEmpty) return '';
  items.sort((a, b) => a.trim().length.compareTo(b.trim().length));
  return _clean(items.first);
}

/// 从套题的分组条目里构造 A/B/C 分段
List<FloatingPart> partsOfGroup(HomeworkGroup group) {
  final list = [...group.entries]
    ..sort((a, b) {
      final ao = a.partOrder, bo = b.partOrder;
      if (ao != null && bo != null) return ao.compareTo(bo);
      if (ao != null) return -1;
      if (bo != null) return 1;
      return a.mtime.compareTo(b.mtime);
    });
  final out = <FloatingPart>[];
  for (var i = 0; i < list.length; i++) {
    final e = list[i];
    final c = e.content;
    final label =
        e.partLabel?.replaceAll('Part ', '').trim() ??
        String.fromCharCode(65 + i); // A/B/C
    if (c == null) {
      out.add(FloatingPart(label, _clean(e.title)));
      continue;
    }
    String body;
    switch (c.structure) {
      case EtsStructure.read:
        // 模仿朗读：朗读原文
        body = _clean(c.text);
      case EtsStructure.threeQ5A:
        // 角色扮演：3 问的英文问题 + 5 答里最短的参考答案
        final asks = c.questions
            .map((q) => q.ask)
            .where((t) => t.trim().isNotEmpty)
            .map(_clean)
            .toList();
        final ans = _shortest(c.stdAnswers.map((a) => a.value).toList());
        body = [
          if (asks.isNotEmpty) asks.join('\n'),
          if (ans.isNotEmpty) ans,
        ].join('\n\n');
      case EtsStructure.picture:
        // 故事复述：最短的范文
        final std = _shortest(c.stdAnswers.map((a) => a.value).toList());
        body = std.isNotEmpty ? std : _clean(c.text);
      default:
        body = _clean(c.text.isNotEmpty ? c.text : c.aiText);
    }
    out.add(FloatingPart(label, body));
  }
  return out;
}
