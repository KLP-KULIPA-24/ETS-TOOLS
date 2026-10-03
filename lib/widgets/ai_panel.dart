import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../services/ai_service.dart';

/// AI 输出统一字号（docs/style-pack/tokens.json：正文 14，标题 18/w600）
final kAiMarkdownConfig = MarkdownConfig(
  configs: [
    const PConfig(textStyle: TextStyle(fontSize: 14, height: 1.5)),
    const H1Config(
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.4),
    ),
    const H2Config(
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.4),
    ),
    const H3Config(style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
    const H4Config(style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
    const H5Config(style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
    const H6Config(style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
  ],
);

/// AI 结果展示（Markdown，流式刷新）
class AiResultView extends StatelessWidget {
  final String text;
  final bool streaming;
  const AiResultView({super.key, required this.text, this.streaming = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MarkdownBlock(
          data: text.isEmpty ? '（等待生成…）' : text,
          config: kAiMarkdownConfig,
          // Column 布局：宽度贴内容、无内部滚动，可安全嵌入聊天气泡与
          // 外层滚动容器（MarkdownWidget 的 ListView 在无界高度会崩）
        ),
        if (streaming)
          LinearProgressIndicator(
            minHeight: 2,
            color: cs.primary,
            backgroundColor: cs.surfaceContainerHighest,
          ),
      ],
    );
  }
}

/// AI 操作按钮组 + 结果面板（供详情页复用）
class AiPanel extends StatelessWidget {
  final Future<String> Function(AiAction action, ValueChanged<String> onDelta)
  run;
  final Map<AiAction, String> results;
  final Map<AiAction, bool> streaming;
  final ValueChanged<AiAction> onRun;

  const AiPanel({
    super.key,
    required this.run,
    required this.results,
    required this.streaming,
    required this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final actions = AiAction.values;
    return Container(
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Text('AI 智能排版', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              Text(
                'OpenAI 兼容接口',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: cs.outline),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in actions)
                ActionChip(
                  avatar: streaming[a] == true
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          results.containsKey(a)
                              ? Icons.refresh_rounded
                              : Icons.play_arrow_rounded,
                          size: 16,
                        ),
                  label: Text(
                    results.containsKey(a) ? '${a.label}（重新生成）' : a.label,
                  ),
                  onPressed: streaming[a] == true ? null : () => onRun(a),
                ),
            ],
          ),
          for (final a in actions)
            if (results[a] != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: AiResultView(
                  text: results[a]!,
                  streaming: streaming[a] == true,
                ),
              ),
            ],
        ],
      ),
    );
  }
}
