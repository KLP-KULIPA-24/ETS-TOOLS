import 'package:flutter/material.dart';

import 'smart_text.dart';

/// E听说富文本工具：清理 </br> </p><p> <p> 等标记
class EtsText {
  /// 转为段落数组
  static List<String> paragraphs(String raw) {
    var s = raw
        .replaceAll('\r\n', '\n')
        .replaceAll('</br>', '\n')
        .replaceAll('<br>', '\n')
        .replaceAll('<br/>', '\n')
        .replaceAll(RegExp(r'</p>\s*<p>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    return s.split('\n').map((e) => e.trim()).toList();
  }

  /// 单字符串（含换行）
  static String clean(String raw) => paragraphs(raw).join('\n');
}

/// E听说文本展示组件
class EtsTextView extends StatelessWidget {
  final String raw;
  final TextStyle? style;
  final bool selectable;
  final TextAlign textAlign;

  const EtsTextView(
    this.raw, {
    super.key,
    this.style,
    this.selectable = false,
    this.textAlign = TextAlign.left,
  });

  @override
  Widget build(BuildContext context) {
    final paras = EtsText.paragraphs(raw);
    final base = style ?? DefaultTextStyle.of(context).style;
    if (selectable) {
      // 划选智能文本：复制 / 翻译（AI）/ 朗读
      return SmartSelectableText(
        EtsText.clean(raw),
        style: base,
        textAlign: textAlign,
      );
    }
    final List<InlineSpan> spans = [];
    for (var i = 0; i < paras.length; i++) {
      if (i > 0) spans.add(const TextSpan(text: '\n'));
      spans.add(TextSpan(text: paras[i], style: base));
    }
    return Text.rich(TextSpan(children: spans), textAlign: textAlign);
  }
}
