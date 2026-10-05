import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/ets_models.dart';
import '../../services/floating_bridge.dart';
import '../../services/floating_parts.dart';
import '../../services/audio_player_service.dart';
import '../../services/lexicon_service.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';
import '../detail/content_detail_page.dart';

/// 分组（文件夹）页面：
/// 单词组 → 单词本样式（大字单词 + 释义 + 发音，可隐藏释义自测）
/// 其他组 → 作业卡片列表
class GroupPage extends StatefulWidget {
  final HomeworkGroup group;
  const GroupPage({super.key, required this.group});

  @override
  State<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<GroupPage> {
  bool hideMeaning = false;

  @override
  void initState() {
    super.initState();
    // 套题 = 一份卷子的 A/B/C 三段：把分段内容同步给悬浮窗，
    // 顶栏按钮一按就能按段切换查看
    final parts = partsOfGroup(widget.group);
    FloatingBridge.set(
      title: widget.group.displayName,
      answers: parts.map((e) => e.text).join('\n\n'),
      parts: [for (final e in parts) {'label': e.label, 'text': e.text}],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isWord = widget.group.structure == EtsStructure.word;

    return GlassScaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.group.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18),
            ),
            Text(
              '共 ${widget.group.entries.length} 项',
              style: TextStyle(fontSize: 12, color: cs.outline),
            ),
          ],
        ),
        actions: [
          if (isWord)
            IconButton(
              tooltip: hideMeaning ? '显示释义' : '隐藏释义（自测模式）',
              isSelected: hideMeaning,
              onPressed: () => setState(() => hideMeaning = !hideMeaning),
              icon: Icon(
                hideMeaning
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_outlined,
              ),
            ),
        ],
      ),
      body: isWord
          ? _WordListView(
              entries: widget.group.entries,
              hideMeaning: hideMeaning,
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final e in widget.group.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _EntryTile(entry: e),
                  ),
              ],
            ),
    );
  }
}

/// 单词本列表
class _WordListView extends StatefulWidget {
  final List<HomeworkEntry> entries;
  final bool hideMeaning;
  const _WordListView({required this.entries, required this.hideMeaning});

  @override
  State<_WordListView> createState() => _WordListViewState();
}

class _WordListViewState extends State<_WordListView> {
  Timer? _ticker;
  String _playingSource = '';

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final src = AudioPlayerService.I.currentSource;
      if (src != _playingSource && mounted) {
        setState(() => _playingSource = src);
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
      itemCount: widget.entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final e = widget.entries[i];
        final c = e.content!;
        final lex = LexiconService.I.lookup(c.text);
        final audio = c.audio.isEmpty ? '' : '${c.dir}/material/${c.audio}';
        final playing = audio.isNotEmpty && _playingSource == audio;

        return Card(
          elevation: 0,
          color: playing
              ? cs.primaryContainer.withValues(alpha: 0.5)
              : cs.surfaceContainerLowest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: playing
                  ? cs.primary
                  : cs.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ContentDetailPage(entry: e)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: cs.outline,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.text,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (lex != null &&
                            (lex.phonUs.isNotEmpty || lex.phonEn.isNotEmpty))
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              [
                                if (lex.phonUs.isNotEmpty) '美 ${lex.phonUs}',
                                if (lex.phonEn.isNotEmpty) '英 ${lex.phonEn}',
                              ].join('  '),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: cs.outline),
                            ),
                          ),
                        if (c.translate.isNotEmpty)
                          widget.hideMeaning
                              ? BlurReveal(
                                  child: Text(
                                    c.translate,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                )
                              : Text(
                                  c.translate,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: cs.primary),
                                ),
                      ],
                    ),
                  ),
                  if (audio.isNotEmpty)
                    IconButton(
                      tooltip: '播放发音',
                      onPressed: () => AudioPlayerService.I.open(audio),
                      icon: Icon(
                        playing && AudioPlayerService.I.playing
                            ? Icons.pause_circle_rounded
                            : Icons.volume_up_rounded,
                        color: cs.primary,
                      ),
                    ),
                  Icon(Icons.chevron_right_rounded, color: cs.outline),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 组内普通作业条目
class _EntryTile extends StatelessWidget {
  final HomeworkEntry entry;
  const _EntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ContentDetailPage(entry: entry)),
        ),
        title: Row(
          children: [
            if (entry.partLabel != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.4)),
                ),
                child: Text(
                  entry.partLabel!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        subtitle: Text('题号 ${entry.content?.stid ?? entry.paper?.tzid ?? '-'}'),
        trailing: TypeBadge(entry.structure),
      ),
    );
  }
}
