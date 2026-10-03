import 'package:flutter/material.dart';

import '../../models/ets_models.dart';
import '../../widgets/audio_bar.dart';
import '../../widgets/common.dart';
import '../../widgets/ets_text.dart';
import 'typed_views.dart';

/// 完整套题（paper.Jason）视图
class PaperDetailView extends StatelessWidget {
  final PaperUnit paper;
  final bool hideAnswers;

  const PaperDetailView({
    super.key,
    required this.paper,
    required this.hideAnswers,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          title: '套题信息',
          icon: Icons.info_outline_rounded,
          children: [
            Row(
              children: [
                Text(
                  '总分 ${paper.totalScore.toStringAsFixed(0)} 分',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(width: 12),
                for (final s in paper.sections)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('${s.name} ${s.score}分'),
                      labelStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ],
        ),
        for (final sec in paper.sections) ...[
          SectionCard(
            title: '${sec.name}（${sec.items.length} 题）',
            icon: Icons.category_rounded,
            children: [
              for (final q in sec.items)
                _PaperQuestionView(
                  question: q,
                  section: sec,
                  paper: paper,
                  hideAnswers: hideAnswers,
                ),
            ],
          ),
        ],
        const SizedBox(height: 40),
      ],
    );
  }
}

class _PaperQuestionView extends StatelessWidget {
  final PaperQuestion question;
  final PaperSection section;
  final PaperUnit paper;
  final bool hideAnswers;

  const _PaperQuestionView({
    required this.question,
    required this.section,
    required this.paper,
    required this.hideAnswers,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final audioPath = question.audio.isEmpty
        ? ''
        : '${paper.dir}/material/${question.audio}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '题 ${question.stid}',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Text(
                '${question.score}分',
                style: TextStyle(fontSize: 12, color: cs.outline),
              ),
              const Spacer(),
            ],
          ),
          if (question.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            EtsTextView(question.text, style: const TextStyle(height: 1.6)),
          ],
          if (audioPath.isNotEmpty) ...[
            const SizedBox(height: 8),
            AudioBar(
              source: audioPath,
              title: '题目音频',
              compact: true,
              showAbLoop: false,
            ),
          ],
          if (question.sentences.isNotEmpty) ...[
            const SizedBox(height: 8),
            SentenceListView(
              sentences: question.sentences,
              audioFile: audioPath,
              hideTranslate: false,
            ),
          ],
        ],
      ),
    );
  }
}
