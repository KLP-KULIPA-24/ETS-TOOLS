import io

# ---------- 1) GroupPage：背景统一 + AppCard + 音标 ----------
p = 'lib/pages/group_page.dart'
s = io.open(p, encoding='utf-8').read()

s = s.replace('''import 'package:flutter/material.dart';

import '../services/audio_player_service.dart';''',
'''import 'package:flutter/material.dart';

import '../services/audio_player_service.dart';
import '../services/lexicon_service.dart';
import '../widgets/glass.dart';''')

s = s.replace('''    return Scaffold(
      appBar: AppBar(''', '''    return GlassScaffold(
      appBar: AppBar(''')

# 单词行：加音标 + 卡片换 AppCard
s = s.replace('''    return Card(
      elevation: 0,
      color: playing
          ? cs.primaryContainer.withValues(alpha: 0.5)
          : cs.surfaceContainerLowest,''',
'''    final lex = LexiconService.I.lookup(c.text);
    return AppCard(
      onTapColor: playing
          ? cs.primaryContainer.withValues(alpha: 0.5)
          : cs.surfaceContainerLowest,''')

s = s.replace('''                        if (c.translate.isNotEmpty)
                          widget.hideMeaning
                              ? BlurReveal(
                                  child: Text(c.translate,
                                      style:
                                          Theme.of(context).textTheme.bodySmall))
                              : Text(c.translate,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: cs.primary)),''',
'''                        if (lex != null &&
                            (lex.phonUs.isNotEmpty || lex.phonEn.isNotEmpty))
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              [
                                if (lex.phonUs.isNotEmpty)
                                  '美 ${lex.phonUs}',
                                if (lex.phonEn.isNotEmpty)
                                  '英 ${lex.phonEn}',
                              ].join('  '),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: cs.outline),
                            ),
                          ),
                        if (c.translate.isNotEmpty)
                          widget.hideMeaning
                              ? BlurReveal(
                                  child: Text(c.translate,
                                      style:
                                          Theme.of(context).textTheme.bodySmall))
                              : Text(c.translate,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: cs.primary)),''')

# GroupPage 状态初始化词典
s = s.replace('''  @override
  void initState() {
    super.initState();
    _load();''', '''  @override
  void initState() {
    super.initState();
    LexiconService.I.ensureLoaded();
    _load();''') if 'void _load()' in s else s

io.open(p, 'w', encoding='utf-8').write(s)
print('group page ok')

# ---------- 2) 三问五答宽屏左右分栏 ----------
p = 'lib/pages/detail/typed_views.dart'
s = io.open(p, encoding='utf-8').read()

old = '''  @override
  Widget build(BuildContext context) {
    final body = switch (c.structure) {
      EtsStructure.threeQ5A => _q5aView(context),'''
new = '''  @override
  Widget build(BuildContext context) {
    // 宽屏（平板/电脑）：三问五答左右分栏 —— 左侧材料/原文，右侧问答
    if (c.structure == EtsStructure.threeQ5A &&
        MediaQuery.of(context).size.width >= 1100) {
      return _q5aWide(context);
    }
    final body = switch (c.structure) {
      EtsStructure.threeQ5A => _q5aView(context),'''
assert old in s, 'build dispatch not found'
s = s.replace(old, new, 1)

# _q5aWide 实现
s = s.replace('''  // ---------- 材料区（音频 + 图片） ----------''',
'''  // ---------- 三问五答 宽屏左右分栏 ----------
  Widget _q5aWide(BuildContext context) {
    final qs = c.questions;
    final partA = qs.where((q) => RegExp(r'[\\u4e00-\\u9fff]').hasMatch(q.ask)).toList();
    final partB = qs.where((q) => !RegExp(r'[\\u4e00-\\u9fff]').hasMatch(q.ask)).toList();
    final img = c.image.isNotEmpty ? _materialPath(c.image) : '';
    final imgWidget = (img.isNotEmpty && File(img).existsSync())
        ? Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.38,
                    maxHeight: 300),
                child: Image.file(File(img), fit: BoxFit.scaleDown),
              ),
            ),
          )
        : const SizedBox.shrink();

    Widget section(String t, IconData ic, List<Widget> children) {
      return SectionCard(title: t, icon: ic, children: children);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左：材料 + 音频 + 情景原文
        Expanded(
          flex: 5,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _materialSection(context),
                const SizedBox(height: 14),
                if (EtsText.clean(c.text).isNotEmpty)
                  section('情景原文', Icons.subject_rounded, [
                    EtsTextView(c.text,
                        selectable: true,
                        style: const TextStyle(height: 1.6)),
                  ]),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        // 右：三问 + 五答
        Expanded(
          flex: 6,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                imgWidget,
                if (partA.isNotEmpty)
                  section('三问 · 用英语提问', Icons.record_voice_over_rounded, [
                    for (final q in partA)
                      _QCard(q: q, hide: widget.hideAnswers, dir: c.dir),
                  ]),
                if (partB.isNotEmpty)
                  section('五答 · 用英语回答', Icons.question_answer_rounded, [
                    for (final q in partB)
                      _QCard(q: q, hide: widget.hideAnswers, dir: c.dir),
                  ]),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------- 材料区（音频 + 图片） ----------''', 1)

io.open(p, 'w', encoding='utf-8').write(s)
print('wide layout ok')
