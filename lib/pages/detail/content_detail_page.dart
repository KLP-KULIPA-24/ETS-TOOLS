import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/ets_models.dart';
import '../../services/ai_service.dart';
import '../../services/floating_bridge.dart';
import '../../widgets/ai_panel.dart';
import '../ai/ai_chat_page.dart';
import '../homework/exam_sim_page.dart';
import '../../widgets/glass.dart';
import '../../widgets/interactive_tour.dart';
import 'paper_detail_view.dart';
import 'typed_views.dart';

/// 作业详情页：按题型分发渲染
class ContentDetailPage extends StatefulWidget {
  final HomeworkEntry entry;
  const ContentDetailPage({super.key, required this.entry});

  @override
  State<ContentDetailPage> createState() => _ContentDetailPageState();
}

class _ContentDetailPageState extends State<ContentDetailPage> {
  bool hideAnswers = false;
  final Map<AiAction, bool> _cached = {};

  // 互动教程锚点
  final _kAiMenu = GlobalKey();
  final _kHideAnswers = GlobalKey();
  final _kFloating = GlobalKey();
  final _kMore = GlobalKey();

  @override
  void initState() {
    super.initState();
    final stid = widget.entry.content?.stid;
    if (stid != null) {
      for (final a in AiAction.values) {
        AiService.I.getCached(stid, a).then((v) {
          if (v != null && v.isNotEmpty && mounted) {
            setState(() => _cached[a] = true);
          }
        });
      }
    }
  }

  String get _plainAnswers => widget.entry.content != null
      ? TypedContentView.plainAnswerText(widget.entry.content!)
      : widget.entry.title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final e = widget.entry;

    Widget body;
    if (e.paper != null) {
      body = PaperDetailView(paper: e.paper!, hideAnswers: hideAnswers);
    } else {
      body = TypedContentView(
        content: e.content!,
        hideAnswers: hideAnswers,
        entryTitle: e.title,
        partLabel: e.partLabel,
      );
    }

    return GlassScaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              e.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18),
            ),
            Text(
              '${e.partLabel != null ? '${e.partLabel} · ' : ''}'
              '${e.structure.label} · 标题来源：${e.titleSource.label}',
              style: TextStyle(fontSize: 12, color: cs.outline),
            ),
          ],
        ),
        actions: [
          // AI 顶部菜单：解析 / 翻译 / 标题 / 实时对话
          PopupMenuButton<String>(
            key: _kAiMenu,
            tooltip: 'AI 功能',
            icon: const Icon(Icons.auto_awesome_rounded),
            onSelected: (v) {
              if (v == 'chat') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AiChatPage(
                      historyKey: e.content?.stid ?? e.paper?.tzid ?? 'global',
                      contextTitle: e.title,
                      contextText: _plainAnswers,
                    ),
                  ),
                );
              } else {
                _openAiSheet(context, v);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'analyze',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.insights_rounded),
                  trailing: _cached[AiAction.analyze] == true
                      ? const Icon(Icons.check_circle_rounded, size: 15)
                      : null,
                  title: Text('智能解析'),
                ),
              ),
              PopupMenuItem(
                value: 'translate',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.translate_rounded),
                  trailing: _cached[AiAction.translate] == true
                      ? const Icon(Icons.check_circle_rounded, size: 15)
                      : null,
                  title: Text('全文翻译'),
                ),
              ),
              PopupMenuItem(
                value: 'title',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.title_rounded),
                  trailing: _cached[AiAction.title] == true
                      ? const Icon(Icons.check_circle_rounded, size: 15)
                      : null,
                  title: Text('AI 标题'),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'chat',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.forum_rounded),
                  title: Text('AI 实时对话'),
                ),
              ),
            ],
          ),
          // 背题模式
          IconButton(
            key: _kHideAnswers,
            tooltip: hideAnswers ? '背题模式（已隐藏答案）' : '隐藏答案（背题模式）',
            isSelected: hideAnswers,
            onPressed: () => setState(() => hideAnswers = !hideAnswers),
            icon: Icon(
              hideAnswers
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_outlined,
            ),
          ),
          // 悬浮窗（仅 Android 系统悬浮球；Windows 已下线该功能）
          if (Platform.isAndroid)
            IconButton(
              key: _kFloating,
              tooltip: '悬浮窗展示答案',
              onPressed: () => _showFloating(),
              icon: const Icon(Icons.picture_in_picture_alt_rounded),
            ),
          // 模拟考场
          PopupMenuButton<String>(
            key: _kMore,
            tooltip: '更多',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) {
              if (v == 'exam') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ExamSimPage(entry: e)),
                );
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'exam',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.mic_rounded),
                  title: Text('模拟考场'),
                  subtitle: Text('按原软件流程播放/倒计时/录音'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: '本页说明',
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: () => InteractiveTour.show(context, _buildTour()),
          ),
        ],
      ),
      body: body,
    );
  }

  /// 作业详情页引导：顶栏四组操作 + 正文精听
  List<TourStep> _buildTour() => [
    TourStep(
      _kAiMenu,
      'AI 功能',
      '智能解析 / 全文翻译 / AI 标题 / 实时对话都在这里；'
          '已生成过的项会打勾（结果有缓存，重复打开不重复扣额度）。',
    ),
    TourStep(_kHideAnswers, '背题模式', '一键隐藏全部答案用于自测，点任意模糊处或再点一次即可恢复。'),
    TourStep(
      _kFloating,
      '悬浮窗展示答案',
      '把答案推到系统悬浮球：点右上角悬浮球收起/展开，'
          '切到别的窗口也能随时看答案。',
    ),
    TourStep(_kMore, '模拟考场', '按原软件流程复现考试：播放 → 倒计时 → 录音 → 回放，可中途跳过。'),
    TourStep(
      null,
      '精听与逐句播放',
      '下方音频条可倍速 0.6x–2.0x、A-B 循环；'
          '有逐句时间轴的题型可点句子右侧 ▶ 只听该句区间。',
    ),
  ];

  Future<void> _showFloating() async {
    await FloatingBridge.set(
      title: widget.entry.title,
      answers: _plainAnswers,
      stid: widget.entry.content?.stid ?? widget.entry.paper?.tzid ?? '',
    );
    if (!Platform.isAndroid) return; // Windows 已取消悬浮窗
    final ok = await FloatingBridge.showAndroidOverlay();
    if (!ok && mounted) {
      // requestPermission() 失败时插件已尝试跳系统设置；这里给出明确路径指引
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 8),
          content: Text(
            '未获得悬浮窗权限：请在系统「设置 → 应用 → 特殊应用权限 → 显示在其他应用上层」'
            '允许本应用后，再点一次悬浮窗按钮',
          ),
        ),
      );
    }
  }

  /// 顶部 AI 菜单 → 结果面板（流式，支持多模型故障切换）
  Future<void> _openAiSheet(BuildContext context, String action) async {
    if (widget.entry.content == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('该条目暂不支持 AI 动作')));
      return;
    }
    await showModalBottomSheet(
      context: this.context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) => _AiResultSheet(
        content: widget.entry.content!,
        action: AiAction.values.firstWhere((a) => a.id == action),
      ),
    );
  }
}

/// AI 结果底部面板（流式输出）
class _AiResultSheet extends StatefulWidget {
  final ContentUnit content;
  final AiAction action;
  const _AiResultSheet({required this.content, required this.action});

  @override
  State<_AiResultSheet> createState() => _AiResultSheetState();
}

class _AiResultSheetState extends State<_AiResultSheet> {
  String _text = '';
  bool _streaming = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    // 打开先显示缓存（自动回显 AI 工作过的内容），点「重新生成」才再跑
    AiService.I.getCached(widget.content.stid, widget.action).then((c) {
      if (!mounted) return;
      if (c != null && c.isNotEmpty) {
        setState(() {
          _text = c;
          _streaming = false;
        });
      } else {
        _run();
      }
    });
  }

  Future<void> _run() async {
    setState(() {
      _streaming = true;
      _error = '';
    });
    try {
      final out = await AiService.I.run(
        widget.content,
        widget.action,
        force: true,
        onDelta: (d) {
          if (mounted) setState(() => _text += d);
        },
      );
      if (mounted) {
        setState(() {
          _text = out;
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
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      builder: (context, scrollCtrl) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  widget.action.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (!_streaming)
                  TextButton.icon(
                    onPressed: _run,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('重新生成'),
                  ),
              ],
            ),
            const Divider(height: 16),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollCtrl,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error.isNotEmpty)
                      Text(
                        _error,
                        style: TextStyle(color: cs.error, fontSize: 13),
                      )
                    else
                      AiResultView(text: _text, streaming: _streaming),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
