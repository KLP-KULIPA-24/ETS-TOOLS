import 'package:flutter/material.dart';

import '../services/ai_service.dart';
import '../services/settings_service.dart';
import '../services/tts_service.dart';

/// 可划选智能文本：长按/划选弹出 复制 / 全选 / 翻译（AI）/ 朗读
/// 翻译需要已配置 AI；朗读走系统 TTS
class SmartSelectableText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;

  const SmartSelectableText(
    this.text, {
    super.key,
    this.style,
    this.textAlign = TextAlign.left,
  });

  @override
  Widget build(BuildContext context) {
    return SelectableText(
      text,
      style: style,
      textAlign: textAlign,
      contextMenuBuilder: (context, editableTextState) {
        final value = editableTextState.textEditingValue;
        final selection = value.selection.textInside(value.text);
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: editableTextState.contextMenuAnchors,
          buttonItems: [
            ContextMenuButtonItem(
              label: '复制',
              onPressed: () {
                editableTextState.copySelection(SelectionChangedCause.toolbar);
                ContextMenuController.removeAny();
              },
            ),
            ContextMenuButtonItem(
              label: '全选',
              onPressed: () {
                editableTextState.selectAll(SelectionChangedCause.toolbar);
                ContextMenuController.removeAny();
              },
            ),
            if (selection.trim().isNotEmpty) ...[
              ContextMenuButtonItem(
                label: '翻译',
                onPressed: () {
                  ContextMenuController.removeAny();
                  _showTranslateSheet(context, selection.trim());
                },
              ),
              if (TtsService.I.supported)
                ContextMenuButtonItem(
                  label: '朗读',
                  onPressed: () {
                    ContextMenuController.removeAny();
                    TtsService.I.speak(selection.trim());
                  },
                ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _showTranslateSheet(BuildContext context, String source) async {
    final s = SettingsService.I;
    if (!s.aiReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('翻译需要 AI：请先到设置配置模型与 API Key')),
      );
      return;
    }
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _TranslateSheet(source: source),
    );
  }
}

class _TranslateSheet extends StatefulWidget {
  final String source;
  const _TranslateSheet({required this.source});

  @override
  State<_TranslateSheet> createState() => _TranslateSheetState();
}

class _TranslateSheetState extends State<_TranslateSheet> {
  String _result = '';
  bool _streaming = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final out = await AiService.I
          .chatWithFailover(
            messages: [
              {'role': 'system', 'content': '你是专业英中翻译。直接给出翻译结果，不要解释。'},
              {'role': 'user', 'content': widget.source},
            ],
            onDelta: (d) {
              if (mounted) setState(() => _result += d);
            },
          )
          .then((r) => r.$1);
      if (mounted) {
        setState(() {
          _result = out;
          _streaming = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _streaming = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('划选翻译', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              widget.source,
              style: TextStyle(fontSize: 12, color: cs.outline),
            ),
            const Divider(height: 16),
            if (_error.isNotEmpty)
              Text(_error, style: TextStyle(color: cs.error, fontSize: 13))
            else
              // 长译文/流式输出必须限高滚动，否则整块顶出屏幕
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight:
                      MediaQuery.sizeOf(context).height * 0.5 -
                      MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _result.isEmpty ? '翻译中…' : _result,
                    style: const TextStyle(fontSize: 14, height: 1.6),
                  ),
                ),
              ),
            if (_streaming)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        ),
      ),
    );
  }
}
