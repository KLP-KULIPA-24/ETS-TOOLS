import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../models/ets_models.dart';
import '../../services/ai_service.dart';
import '../../services/audio_player_service.dart';
import '../../services/lexicon_service.dart';
import '../../services/media_share.dart';
import '../../services/settings_service.dart';
import '../../services/tts_service.dart';
import '../../widgets/audio_bar.dart';
import '../../widgets/common.dart';
import '../../widgets/ets_text.dart';
import '../../widgets/smart_text.dart';
import '../../widgets/inline_audio_button.dart';
import '../../widgets/ktv_text.dart';
import '../../widgets/video_card.dart';

/// 按题型分发的内容视图
class TypedContentView extends StatefulWidget {
  final ContentUnit content;
  final bool hideAnswers;

  /// 保存文件名用：套卷/作业标题、部分标识（Part A/B/C）
  final String entryTitle;
  final String? partLabel;

  const TypedContentView({
    super.key,
    required this.content,
    required this.hideAnswers,
    this.entryTitle = '',
    this.partLabel,
  });

  /// 纯文本答案（悬浮窗用）
  static String plainAnswerText(ContentUnit c) {
    final sb = StringBuffer();
    switch (c.structure) {
      case EtsStructure.threeQ5A:
        for (final q in c.questions) {
          sb.writeln('${q.xh}. ${q.ask}');
          if (q.role == 'a' && q.answer.isNotEmpty) {
            sb.writeln('答: ${q.answer}');
          } else if (q.std.isNotEmpty) {
            sb.writeln('答: ${q.std.first.value}');
          }
          sb.writeln();
        }
      case EtsStructure.word:
        sb.writeln('${c.text}\n${c.translate}');
      case EtsStructure.picture:
        if (c.stdAnswers.isNotEmpty) {
          sb.writeln(EtsText.clean(c.stdAnswers.first.value));
        }
        if (c.keypoint.isNotEmpty) {
          sb.writeln('\n要点: ${EtsText.clean(c.keypoint)}');
        }
      case EtsStructure.repeatDialogue:
        for (final s in c.sentences) {
          sb.writeln('${s.role}: ${s.text}');
          if (s.translate.isNotEmpty) sb.writeln('译: ${s.translate}');
        }
      default:
        sb.writeln(EtsText.clean(c.text));
        if (c.translate.isNotEmpty) sb.writeln('\n${c.translate}');
    }
    return sb.toString();
  }

  @override
  State<TypedContentView> createState() => _TypedContentViewState();
}

/// 全屏图片弹层的底部操作按钮（深色底上的白色胶囊）
Widget _imgBtn(
  BuildContext context,
  IconData icon,
  String label,
  VoidCallback onTap,
) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.white.withValues(alpha: 0.14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 13)),
    ),
  );
}

/// 划词菜单：选中文字后可朗读 / 查释义 / 复制（本地功能，零配置）
Widget selMenuBuilder(BuildContext context, EditableTextState state) {
  final tev = state.textEditingValue;
  final selSel = tev.selection;
  final sel = (selSel.isValid && selSel.start != selSel.end)
      ? tev.text
            .substring(
              selSel.start.clamp(0, tev.text.length),
              selSel.end.clamp(0, tev.text.length),
            )
            .trim()
      : '';
  void close() => ContextMenuController.removeAny();
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: state.contextMenuAnchors,
    buttonItems: [
      if (sel.isNotEmpty) ...[
        ContextMenuButtonItem(
          label: '朗读',
          onPressed: () {
            close();
            TtsService.I.speak(sel);
          },
        ),
        ContextMenuButtonItem(
          label: '释义',
          onPressed: () {
            close();
            showWordSheet(context, sel);
          },
        ),
      ],
      ContextMenuButtonItem(
        label: '复制',
        onPressed: () {
          close();
          Clipboard.setData(ClipboardData(text: sel));
        },
      ),
    ],
  );
}

/// 划词「问 AI」：把选中内容交给 AI 解释（流式显示在弹层里）
void showAskAiSheet(BuildContext context, String sel) {
  final s = SettingsService.I;
  if (!s.aiReady) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('请先到「设置 → AI 配置」添加模型并填写 API Key')),
    );
    return;
  }
  final buf = StringBuffer();
  var done = false;
  String? err;
  var running = false;
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      Future<void> run(StateSetter setSheet) async {
        if (running) return;
        running = true;
        try {
          await AiService.I.chatWithFailover(
            messages: [
              {
                'role': 'system',
                'content':
                    '你是英语学习助手。用中文解释用户选中的英文（词性、词义、读音提示），'
                    '并给一个例句；若是句子则翻译并讲解要点。简洁，200 字内。',
              },
              {'role': 'user', 'content': sel},
            ],
            onDelta: (d) {
              buf.write(d);
              setSheet(() {});
            },
          );
        } catch (e) {
          err = '$e';
        } finally {
          running = false;
          if (ctx.mounted) setSheet(() => done = true);
        }
      }

      return StatefulBuilder(
        builder: (ctx, setSheet) {
          if (!running && buf.isEmpty && err == null) {
            // 弹层出现即请求
            WidgetsBinding.instance.addPostFrameCallback((_) => run(setSheet));
          }
          final cs = Theme.of(ctx).colorScheme;
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                20 + MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 18,
                        color: cs.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          sel.length > 40 ? '${sel.substring(0, 40)}…' : sel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '朗读',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => TtsService.I.speak(sel),
                        icon: const Icon(
                          Icons.record_voice_over_rounded,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: SingleChildScrollView(
                      child: err != null
                          ? Text(
                              '调用失败：$err',
                              style: TextStyle(fontSize: 13, color: cs.error),
                            )
                          : Text(
                              buf.isEmpty ? '正在思考…' : buf.toString(),
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.65,
                              ),
                            ),
                    ),
                  ),
                  if (done && err == null && buf.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: buf.toString()),
                            );
                          },
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: const Text('复制回答'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// 单词释义弹层：内置词典（音标/释义/原版发音）+ TTS 朗读
void showWordSheet(BuildContext context, String raw) {
  final word = raw.trim().split(RegExp(r'\s+')).first;
  final lex = LexiconService.I.lookup(word);
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                word,
                style: Theme.of(ctx).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              if (lex != null) ...[
                if (lex.phonUs.isNotEmpty || lex.phonEn.isNotEmpty)
                  Text(
                    [
                      if (lex.phonUs.isNotEmpty) '美 ${lex.phonUs}',
                      if (lex.phonEn.isNotEmpty) '英 ${lex.phonEn}',
                    ].join('   '),
                    style: TextStyle(fontSize: 13, color: cs.outline),
                  ),
                const SizedBox(height: 8),
                Text(
                  lex.trans,
                  style: const TextStyle(fontSize: 15, height: 1.5),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  children: [
                    if (lex.audioUs.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => AudioPlayerService.I.open(lex.audioUs),
                        icon: const Icon(Icons.volume_up_rounded, size: 16),
                        label: const Text('美音'),
                      ),
                    if (lex.audioEn.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => AudioPlayerService.I.open(lex.audioEn),
                        icon: const Icon(Icons.volume_up_rounded, size: 16),
                        label: const Text('英音'),
                      ),
                    FilledButton.icon(
                      onPressed: () => TtsService.I.speak(word),
                      icon: const Icon(
                        Icons.record_voice_over_rounded,
                        size: 16,
                      ),
                      label: const Text('朗读'),
                    ),
                  ],
                ),
              ] else ...[
                Text(
                  '内置词典暂未收录这个词。',
                  style: TextStyle(fontSize: 13, color: cs.outline),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          TtsService.I.speak(word);
                          Navigator.of(ctx).pop();
                        },
                        icon: const Icon(
                          Icons.record_voice_over_rounded,
                          size: 16,
                        ),
                        label: const Text('朗读这个词'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _TypedContentViewState extends State<TypedContentView> {
  ContentUnit get c => widget.content;

  String _materialPath(String file) =>
      file.isEmpty ? '' : '${c.dir}/material/$file';

  /// 界面展示名：套卷名 · 题型(Part) · 类型（不露 content.mp3 这类原始文件名）
  String _displayLabel(String kind) {
    final parts = <String>[
      if (widget.entryTitle.isNotEmpty) widget.entryTitle,
      widget.partLabel == null
          ? c.structure.label
          : '${c.structure.label}(${widget.partLabel})',
      kind,
    ];
    return parts.join(' · ');
  }

  /// 保存文件名：套卷名-题型(Part)-语义名（**不含 content.mp3 这类原始文件名**）
  /// 例：期末测试A-模仿朗读(Part A)-完整录音.mp3
  String _saveName(String kind, String ext) {
    final base = <String>[
      if (widget.entryTitle.isNotEmpty) widget.entryTitle,
      widget.partLabel == null
          ? c.structure.label
          : '${c.structure.label}(${widget.partLabel})',
      kind,
    ].join('-');
    return '$base$ext';
  }

  @override
  Widget build(BuildContext context) {
    // 宽屏（平板/电脑）：三问五答左右分栏 —— 左侧材料/原文，右侧问答
    if (c.structure == EtsStructure.threeQ5A &&
        MediaQuery.of(context).size.width >= 1100) {
      return _q5aWide(context);
    }
    // 宽屏（平板/电脑）：模仿朗读左右分栏 —— 左侧视频/音频材料，右侧朗读原文
    if (c.structure == EtsStructure.read &&
        MediaQuery.of(context).size.width >= 1100) {
      return _readWide(context);
    }
    final body = switch (c.structure) {
      EtsStructure.threeQ5A => _q5aView(context),
      EtsStructure.word => _wordView(context),
      EtsStructure.read => _readView(context),
      EtsStructure.picture => _pictureView(context),
      EtsStructure.repeatDialogue => _repeatDialogueView(context),
      EtsStructure.unknown => _unknownView(context),
    };
    return RefreshIndicator(
      onRefresh: () async {},
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _materialSection(context),
          const SizedBox(height: 14),
          body,
          // AI 功能在顶部 AppBar 菜单（解析/翻译/标题/实时对话）
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ---------- 三问五答 宽屏左右分栏 ----------
  Widget _q5aWide(BuildContext context) {
    final qs = c.questions;
    final partA = qs
        .where((q) => RegExp(r'[\u4e00-\u9fff]').hasMatch(q.ask))
        .toList();
    final partB = qs
        .where((q) => !RegExp(r'[\u4e00-\u9fff]').hasMatch(q.ask))
        .toList();

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
                    EtsTextView(
                      c.text,
                      selectable: true,
                      style: const TextStyle(height: 1.6),
                    ),
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

  // ---------- 材料区（视频 + 音频 + 图片） ----------
  Widget _materialSection(BuildContext context) {
    final children = <Widget>[];
    // 模仿朗读：原版考试视频（content.mp4）优先展示——视频里有朗读画面与字幕
    final vid = c.video.isNotEmpty ? _materialPath(c.video) : '';
    if (vid.isNotEmpty && File(vid).existsSync()) {
      children.add(
        VideoCard(
          source: vid,
          title: _displayLabel('考试视频'),
          targetName: _saveName('考试视频', p.extension(c.video)),
        ),
      );
      children.add(const SizedBox(height: 10));
    }
    final img = c.image.isNotEmpty ? _materialPath(c.image) : '';
    if (img.isNotEmpty && File(img).existsSync()) {
      children.add(
        Center(
          child: GestureDetector(
            // 点击全屏查看，可双指缩放——看图说话的题图常需要放大辨认细节
            onTap: () => _openImageFullscreen(
              context,
              img,
              targetName: _saveName('题图', p.extension(c.image)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.86,
                  maxHeight: 360,
                ),
                child: Image.file(
                  File(img),
                  fit: BoxFit.scaleDown, // 保持比例，过大自动缩小，不拉伸不裁剪
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
          ),
        ),
      );
      children.add(const SizedBox(height: 10));
    }
    if (c.audio.isNotEmpty) {
      children.add(
        AudioBar(
          source: _materialPath(c.audio),
          title: _displayLabel('完整录音'),
          targetName: _saveName('完整录音', p.extension(c.audio)),
        ),
      );
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return SectionCard(
      title: '材料',
      icon: Icons.graphic_eq_rounded,
      children: children,
    );
  }

  /// 播放/停止某一份范文：播放时展开进度条 + KTV 逐句高亮
  /// TTS 朗读按钮：朗读中切换为停止图标；系统无英语语音时禁用并提示用原版录音
  Widget _ttsBtn(String text, {String tip = '朗读'}) {
    final available = TtsService.I.available;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: TtsService.I.speaking,
          builder: (context, on, _) => IconButton(
            tooltip: !available ? '当前系统无英语语音，可用原版录音' : (on ? '停止朗读' : tip),
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            onPressed: available ? () => TtsService.I.toggle(text) : null,
            icon: Icon(
              on ? Icons.stop_circle_rounded : Icons.record_voice_over_rounded,
            ),
          ),
        ),
        // 朗读中：进度条（估算）+ 倍速（点按循环）
        ValueListenableBuilder<bool>(
          valueListenable: TtsService.I.speaking,
          builder: (context, on, _) {
            if (!on) return const SizedBox.shrink();
            final cs = Theme.of(context).colorScheme;
            return Padding(
              padding: const EdgeInsets.only(top: 2),
              // 固定宽：在 Row 里展开不挤压相邻文字
              child: SizedBox(
                width: 180,
                child: Row(
                  children: [
                    Expanded(
                      child: ValueListenableBuilder<double>(
                        valueListenable: TtsService.I.progress,
                        builder: (context, p, _) => ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: p,
                            minHeight: 4,
                            backgroundColor: cs.primary.withValues(alpha: 0.15),
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    ValueListenableBuilder<double>(
                      valueListenable: TtsService.I.rateLabel,
                      builder: (context, r, _) => InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => TtsService.I.cycleRate(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Text(
                            '${r}x',
                            style: TextStyle(fontSize: 11, color: cs.primary),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _playStd(int i, String file) async {
    final ps = AudioPlayerService.I;
    if (_playingStd == i) {
      await ps.pause();
      if (mounted) setState(() => _playingStd = null);
      return;
    }
    await ps.open(file);
    if (!mounted) return;
    setState(() {
      _playingStd = i;
      _stdDur = 0;
    });
    // 等元数据就绪后取时长（KTV 比例分句需要）
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() => _stdDur = ps.duration.inMilliseconds / 1000.0);
  }

  void _openImageFullscreen(
    BuildContext context,
    String path, {
    String? targetName,
  }) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog.fullscreen(
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                maxScale: 5,
                child: Image.file(
                  File(path),
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton.filledTonal(
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            Positioned(
              bottom: 14,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (Platform.isAndroid || Platform.isIOS)
                        _imgBtn(
                          context,
                          Icons.share_rounded,
                          '分享',
                          () => MediaShare.share(context, path),
                        ),
                      _imgBtn(
                        context,
                        Icons.download_rounded,
                        '保存到下载',
                        () => MediaShare.saveAs(
                          context,
                          path,
                          targetName: targetName,
                        ),
                      ),
                      _imgBtn(
                        context,
                        Icons.content_copy_rounded,
                        '复制路径',
                        () => MediaShare.copyPath(context, path),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '双指缩放查看细节',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 三问五答 ----------
  Widget _q5aView(BuildContext context) {
    final qs = c.questions;
    // 三问/五答按 ask 语言判断：中文提示=三问提问，英文=五答回答
    // （部分数据的 role 字段标错，不能依赖）
    bool isAskType(EtsQuestion q) => RegExp(r'[一-鿿]').hasMatch(q.ask);
    final partA = qs.where(isAskType).toList();
    final partB = qs.where((q) => !isAskType(q)).toList();

    return Column(
      children: [
        if (EtsText.clean(c.text).isNotEmpty)
          SectionCard(
            title: '情景原文',
            icon: Icons.subject_rounded,
            children: [
              EtsTextView(c.text, style: const TextStyle(height: 1.6)),
            ],
          ),
        if (partA.isNotEmpty)
          SectionCard(
            title: '三问 · 用英语提问',
            icon: Icons.record_voice_over_rounded,
            children: [
              for (final q in partA)
                _QCard(q: q, hide: widget.hideAnswers, dir: c.dir),
            ],
          ),
        if (partB.isNotEmpty)
          SectionCard(
            title: '五答 · 用英语回答',
            icon: Icons.question_answer_rounded,
            children: [
              for (final q in partB)
                _QCard(q: q, hide: widget.hideAnswers, dir: c.dir),
            ],
          ),
      ],
    );
  }

  // ---------- 单词 ----------
  TextStyle? _phonStyle(ThemeData theme) => theme.textTheme.bodySmall?.copyWith(
    color: theme.colorScheme.onSurfaceVariant,
    height: 1.2,
  );

  LexEntry? _lex;
  int? _playingStd; // 正在播放的范文序号（-1=无）
  double _stdDur = 0; // 当前范文音频时长（比例分句用）

  Widget _wordView(BuildContext context) {
    final theme = Theme.of(context);
    // 异步查词典
    if (_lex == null) {
      LexiconService.I.ensureLoaded().then((_) {
        if (!mounted) return;
        final e = LexiconService.I.lookup(c.text);
        if (e != null) setState(() => _lex = e);
      });
    }
    return SectionCard(
      title: '单词',
      icon: Icons.abc_rounded,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: SelectableText(
                c.text,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // 原版单词音频优先（material 里若带音频）
            Builder(
              builder: (context) {
                final native = c.audio.isNotEmpty ? _materialPath(c.audio) : '';
                if (native.isEmpty || !File(native).existsSync()) {
                  return const SizedBox.shrink();
                }
                return IconButton(
                  tooltip: '播放原版发音 ${c.audio}',
                  onPressed: () => AudioPlayerService.I.open(native),
                  icon: const Icon(Icons.graphic_eq_rounded),
                );
              },
            ),
            // TTS 朗读兜底（无原版音频时也可听）
            _ttsBtn(c.text, tip: '朗读单词'),
          ],
        ),
        const SizedBox(height: 8),
        if (c.translate.isNotEmpty)
          SelectableText(
            c.translate,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        // 音标与发音（来自 E听说 内置词典）
        if (_lex != null) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if ((_lex!.phonUs).isNotEmpty)
                Text('美 ${_lex!.phonUs}', style: _phonStyle(theme)),
              if ((_lex!.phonEn).isNotEmpty)
                Text('英 ${_lex!.phonEn}', style: _phonStyle(theme)),
              if ((_lex!.audioUs).isNotEmpty)
                TextButton.icon(
                  onPressed: () => AudioPlayerService.I.open(_lex!.audioUs),
                  icon: const Icon(Icons.volume_up_rounded, size: 15),
                  label: const Text('美音', style: TextStyle(fontSize: 12)),
                ),
              if ((_lex!.audioEn).isNotEmpty)
                TextButton.icon(
                  onPressed: () => AudioPlayerService.I.open(_lex!.audioEn),
                  icon: const Icon(Icons.volume_up_rounded, size: 15),
                  label: const Text('英音', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ],
        if (c.analyze.isNotEmpty) ...[
          const SizedBox(height: 8),
          EtsTextView(c.analyze, style: theme.textTheme.bodyMedium),
        ],
      ],
    );
  }

  // ---------- 朗读 · 宽屏左右分栏（视频 | 原文） ----------
  Widget _readWide(BuildContext context) {
    final sents = c.sentences.isNotEmpty ? c.sentences : c.parseVideoTime();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左：视频 + 音频材料
        Expanded(
          flex: 5,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [_materialSection(context), const SizedBox(height: 14)],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        // 右：朗读原文（跟读高亮）+ 逐句精听
        Expanded(
          flex: 6,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SectionCard(
                  title: '朗读原文',
                  icon: Icons.article_rounded,
                  children: [
                    KtvText(
                      text: c.text,
                      segments: sents,
                      enabled: context.watch<SettingsService>().followHighlight,
                      menuBuilder: selMenuBuilder,
                      audioFile: c.audio.isEmpty ? '' : _materialPath(c.audio),
                      selectable: true,
                      baseStyle: const TextStyle(height: 1.7, fontSize: 18),
                    ),
                    if (c.translate.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: EtsTextView(
                          c.translate,
                          style: TextStyle(
                            height: 1.6,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (sents.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  SentenceListView(
                    sentences: sents,
                    audioFile: c.audio.isNotEmpty ? _materialPath(c.audio) : '',
                    hideTranslate: false,
                  ),
                ],
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------- 朗读 ----------
  Widget _readView(BuildContext context) {
    final sents = c.sentences.isNotEmpty ? c.sentences : c.parseVideoTime();
    return Column(
      children: [
        SectionCard(
          title: '朗读原文',
          icon: Icons.article_rounded,
          // 播放时逐句染色：已读=主题色，当前句加粗高亮
          children: [
            KtvText(
              text: c.text, // 完整原文底稿：所有字都显示，高亮只染色
              segments: sents,
              enabled: context.watch<SettingsService>().followHighlight,
              menuBuilder: selMenuBuilder,
              audioFile: c.audio.isEmpty ? '' : _materialPath(c.audio),
              selectable: true,
              baseStyle: const TextStyle(height: 1.7, fontSize: 18),
            ),
            if (c.translate.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: EtsTextView(
                  c.translate,
                  style: TextStyle(
                    height: 1.6,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
            ],
          ],
        ),
        if (sents.isNotEmpty)
          SentenceListView(
            sentences: sents,
            audioFile: c.audio.isNotEmpty ? _materialPath(c.audio) : '',
            hideTranslate: false,
          ),
      ],
    );
  }

  // ---------- 故事复述 ----------
  Widget _pictureView(BuildContext context) {
    final stds = c.stdAnswers;
    return Column(
      children: [
        SectionCard(
          title: '故事内容',
          icon: Icons.auto_stories_rounded,
          children: [
            EtsTextView(
              c.text,
              selectable: true,
              style: const TextStyle(height: 1.7),
            ),
          ],
        ),
        if (stds.isNotEmpty)
          SectionCard(
            title: '标准复述范文（共 ${stds.length} 份）',
            icon: Icons.fact_check_rounded,
            children: [
              // 每份范文独立分节：原数据是并列的多个版本，不是一篇
              for (var i = 0; i < stds.length; i++) ...[
                if (i > 0) const Divider(height: 20),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '范文 ${i + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (stds[i].audio.isNotEmpty)
                      Builder(
                        builder: (context) {
                          final f = _materialPath(stds[i].audio);
                          if (!File(f).existsSync()) {
                            return const SizedBox.shrink();
                          }
                          final playing = _playingStd == i;
                          return IconButton(
                            tooltip: playing
                                ? '暂停范文 ${i + 1}'
                                : '播放范文 ${i + 1} 原版录音',
                            visualDensity: VisualDensity.compact,
                            iconSize: 20,
                            onPressed: () => _playStd(i, f),
                            icon: Icon(
                              playing
                                  ? Icons.pause_circle_filled_rounded
                                  : Icons.play_circle_fill_rounded,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          );
                        },
                      ),
                    _ttsBtn(stds[i].value, tip: '朗读范文 ${i + 1}'),
                  ],
                ),
                const SizedBox(height: 6),
                if (_playingStd == i) ...[
                  AudioBar(
                    source: _materialPath(stds[i].audio),
                    title: '范文 ${i + 1} 原版录音',
                    showAbLoop: false,
                    compact: true,
                    targetName: _saveName(
                      '范文${i + 1}',
                      p.extension(stds[i].audio),
                    ),
                  ),
                  const SizedBox(height: 8),
                  KtvText(
                    text: stds[i].value,
                    durationSec: _stdDur,
                    enabled: context.watch<SettingsService>().followHighlight,
                    menuBuilder: selMenuBuilder,
                    audioFile: _materialPath(stds[i].audio),
                    selectable: true,
                  ),
                ] else
                  widget.hideAnswers
                      ? BlurReveal(
                          child: EtsTextView(
                            stds[i].value,
                            style: const TextStyle(height: 1.7),
                          ),
                        )
                      : EtsTextView(
                          stds[i].value,
                          style: const TextStyle(height: 1.7),
                        ),
              ],
            ],
          ),
        if (c.keypoint.isNotEmpty)
          SectionCard(
            title: '要点提示',
            icon: Icons.lightbulb_outline_rounded,
            children: [
              EtsTextView(c.keypoint, style: const TextStyle(height: 1.7)),
            ],
          ),
      ],
    );
  }

  // ---------- 对话跟读 ----------
  Widget _repeatDialogueView(BuildContext context) {
    return SentenceListView(
      sentences: c.sentences,
      audioFile: c.audio.isNotEmpty ? _materialPath(c.audio) : '',
      hideTranslate: false,
    );
  }

  // ---------- 未知题型（AI 自适应） ----------
  Widget _unknownView(BuildContext context) {
    final raw = const JsonEncoder.withIndent('  ').convert(c.info);
    return SectionCard(
      title: '未识别题型 · 原始数据',
      icon: Icons.data_object_rounded,
      trailing: Text(
        'structure_type: ${c.structure.key}',
        style: Theme.of(context).textTheme.labelSmall,
      ),
      children: [
        Text(
          '该题型暂无内置渲染器。下方 AI 面板可用"AI 自适应识别"解析本题；'
          '也可以等新版本内置适配。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(10),
          ),
          child: SingleChildScrollView(
            child: Text(
              raw,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------- 题目卡片（三问五答） ----------
class _QCard extends StatefulWidget {
  final EtsQuestion q;
  final bool hide;
  final String dir;

  const _QCard({required this.q, required this.hide, required this.dir});

  @override
  State<_QCard> createState() => _QCardState();
}

class _QCardState extends State<_QCard> {
  bool _moreAnswers = false;
  bool _moreVariants = false;
  bool _showKeywords = false;
  late final String _shortAnswer; // 默认展示最短答案

  @override
  void initState() {
    super.initState();
    final q = widget.q;
    // 三问（中文提示）：std = 你要问的英文问句；answer = 对话中的答案
    // 五答（英文提问）：answer/std = 答案
    final askIsChinese = RegExp(r'[\u4e00-\u9fff]').hasMatch(q.ask);
    _isAskType = askIsChinese;
    if (askIsChinese) {
      _askVariants = [
        for (final st in q.std)
          if (st.value.trim().isNotEmpty) st.value.trim(),
      ];
      _answerCandidates = [
        if (q.answer.trim().isNotEmpty &&
            !_askVariants.contains(q.answer.trim()))
          q.answer.trim(),
      ];
    } else {
      _askVariants = [];
      _answerCandidates = [
        if (q.answer.trim().isNotEmpty) q.answer.trim(),
        for (final st in q.std)
          if (st.value.trim().isNotEmpty && st.value.trim() != q.answer.trim())
            st.value.trim(),
      ];
      _answerCandidates.sort((a, b) => a.length.compareTo(b.length)); // 最短优先
    }
    _shortAnswer = _answerCandidates.isEmpty ? '' : _answerCandidates.first;
  }

  late bool _isAskType;
  late List<String> _askVariants; // 三问：英文问句变体
  late List<String> _answerCandidates; // 答案候选

  String _mp3(String f) => f.isEmpty ? '' : '${widget.dir}/material/$f';

  /// 三问问句 TTS（该数据中问句录音为空时的兜底）
  Widget _askTtsBtn(BuildContext context, String text, String tip) {
    final cs = Theme.of(context).colorScheme;
    final available = TtsService.I.available;
    return ValueListenableBuilder<bool>(
      valueListenable: TtsService.I.speaking,
      builder: (context, on, _) => IconButton(
        tooltip: !available ? '当前系统无英语语音，可用原版录音' : (on ? '停止朗读' : tip),
        iconSize: 20,
        visualDensity: VisualDensity.compact,
        onPressed: available ? () => TtsService.I.toggle(text) : null,
        icon: Icon(
          on ? Icons.stop_circle_rounded : Icons.record_voice_over_rounded,
          color: on ? cs.primary : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.q;
    final hide = widget.hide;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isAsk = _isAskType;
    final answerText = _shortAnswer;
    final hasMore = _answerCandidates.length > 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 11,
                backgroundColor: isAsk ? cs.primary : cs.tertiary,
                child: Text(
                  q.xh,
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SmartSelectableText(
                  q.ask.trim(),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (q.askAudio.isNotEmpty)
                _AudioDot(file: _mp3(q.askAudio), tip: '播放问题录音'),
              if (q.aswAudio.isNotEmpty)
                _AudioDot(file: _mp3(q.aswAudio), tip: '播放答案录音'),
              if (q.sucai.isNotEmpty)
                _AudioDot(file: _mp3(q.sucai), tip: '播放答案录音'),
            ],
          ),
          // 三问：你要问的英文问句（std 第一条）+ 更多问法
          if (isAsk && _askVariants.isNotEmpty && hide == false) ...[
            const SizedBox(height: 6),
            Text(
              '你要问的英文问题（参考）',
              style: TextStyle(fontSize: 12, color: cs.outline),
            ),
            const SizedBox(height: 3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SmartSelectableText(
                    _askVariants.first,
                    style: TextStyle(
                      height: 1.5,
                      fontSize: 13,
                      color: cs.tertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // 该数据中三问没有问句录音，用 TTS 朗读兜底
                _askTtsBtn(context, _askVariants.first, '朗读英文问句'),
              ],
            ),
            if (_askVariants.length > 1) ...[
              const SizedBox(height: 4),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _moreVariants = !_moreVariants),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _moreVariants
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 15,
                        color: cs.primary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '更多问法（共 ${_askVariants.length} 个）',
                        style: TextStyle(fontSize: 12, color: cs.primary),
                      ),
                    ],
                  ),
                ),
              ),
              if (_moreVariants)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  constraints: const BoxConstraints(maxHeight: 190),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 1; i < _askVariants.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$i. ',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.outline,
                                  ),
                                ),
                                Expanded(
                                  child: SmartSelectableText(
                                    _askVariants[i],
                                    style: const TextStyle(
                                      fontSize: 13,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
          // 答案：三问=对话中的答案；五答=最短参考答案
          if (isAsk && answerText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('对话中的答案', style: TextStyle(fontSize: 12, color: cs.outline)),
            const SizedBox(height: 3),
            hide
                ? BlurReveal(
                    child: SmartSelectableText(
                      answerText,
                      style: const TextStyle(height: 1.6, fontSize: 14),
                    ),
                  )
                : SmartSelectableText(
                    answerText,
                    style: TextStyle(
                      height: 1.6,
                      fontSize: 14,
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ],
          if (!isAsk && answerText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('参考答案（最短）', style: TextStyle(fontSize: 12, color: cs.outline)),
            const SizedBox(height: 3),
            hide
                ? BlurReveal(
                    child: SmartSelectableText(
                      answerText,
                      style: const TextStyle(height: 1.6, fontSize: 14),
                    ),
                  )
                : SmartSelectableText(
                    answerText,
                    style: TextStyle(
                      height: 1.6,
                      fontSize: 14,
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ],
          if (!isAsk && hasMore) ...[
            const SizedBox(height: 6),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _moreAnswers = !_moreAnswers),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _moreAnswers
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 15,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      _moreAnswers
                          ? '收起其他答案'
                          : '更多答案（共 ${_answerCandidates.length} 个）',
                      style: TextStyle(fontSize: 12, color: cs.primary),
                    ),
                  ],
                ),
              ),
            ),
            if (_moreAnswers)
              Container(
                margin: const EdgeInsets.only(top: 6),
                constraints: const BoxConstraints(maxHeight: 190),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < _answerCandidates.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${i + 1}. ',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.outline,
                                ),
                              ),
                              Expanded(
                                child: SmartSelectableText(
                                  _answerCandidates[i],
                                  style: const TextStyle(
                                    fontSize: 13,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
          if (q.keywordList.isNotEmpty) ...[
            const SizedBox(height: 4),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _showKeywords = !_showKeywords),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _showKeywords
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 15,
                      color: cs.outline,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '评分关键词 · ${q.keywordList.length}',
                      style: TextStyle(fontSize: 12, color: cs.outline),
                    ),
                  ],
                ),
              ),
            ),
            if (_showKeywords)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final k in q.keywordList)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: cs.secondaryContainer.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          k,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSecondaryContainer,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _AudioDot extends StatelessWidget {
  final String file;
  final String tip;
  const _AudioDot({required this.file, required this.tip});

  @override
  Widget build(BuildContext context) {
    // 播放中在按钮下方展开小控制条（进度/倍速/暂停）
    return InlineAudioButton(source: file, tip: tip);
  }
}

// ---------- 逐句列表 ----------
class SentenceListView extends StatefulWidget {
  final List<SentenceSeg> sentences;
  final String audioFile; // 完整音频路径（含区间播放）
  final bool hideTranslate;
  const SentenceListView({
    super.key,
    required this.sentences,
    required this.audioFile,
    this.hideTranslate = false,
  });

  @override
  State<SentenceListView> createState() => _SentenceListViewState();
}

class _SentenceListViewState extends State<SentenceListView> {
  Timer? _ticker;
  double _pos = 0;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (!mounted) return;
      final ps = AudioPlayerService.I;
      if (ps.currentSource == widget.audioFile) {
        setState(() => _pos = ps.position.inMilliseconds / 1000.0);
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
    if (widget.sentences.isEmpty) return const SizedBox.shrink();
    return SectionCard(
      title: '逐句精听 / 跟读',
      icon: Icons.format_list_numbered_rounded,
      trailing: widget.audioFile.isEmpty
          ? null
          : Text(
              '点句子右侧 ▶ 播放该句区间',
              style: Theme.of(context).textTheme.labelSmall,
            ),
      children: [
        for (final s in widget.sentences)
          Builder(
            builder: (context) {
              final active =
                  widget.audioFile.isNotEmpty &&
                  AudioPlayerService.I.currentSource == widget.audioFile &&
                  _pos >= s.begin &&
                  _pos < s.end;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: active
                      ? cs.primaryContainer.withValues(alpha: 0.6)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: active
                        ? cs.primary
                        : cs.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        s.seq,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ),
                    if (s.role.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        s.role,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.tertiary,
                        ),
                      ),
                    ],
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(
                            s.text,
                            style: const TextStyle(height: 1.5),
                            // 右键（桌面）/ 长按（手机）→ 朗读 / 问 AI / 复制
                            contextMenuBuilder: selMenuBuilder,
                          ),
                          if (!widget.hideTranslate && s.translate.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                s.translate,
                                style: TextStyle(
                                  height: 1.4,
                                  fontSize: 12,
                                  color: cs.outline,
                                ),
                              ),
                            ),
                          // 朗读进度条（常驻）：TTS 无法 seek，进度为估算；
                          // 右侧「朗读 / 暂停」切换
                          const SizedBox(height: 6),
                          ValueListenableBuilder<bool>(
                            valueListenable: TtsService.I.speaking,
                            builder: (context, sp, _) => Row(
                              children: [
                                Expanded(
                                  child: ValueListenableBuilder<double>(
                                    valueListenable: TtsService.I.progress,
                                    builder: (context, pr, _) => ClipRRect(
                                      borderRadius: BorderRadius.circular(999),
                                      child: LinearProgressIndicator(
                                        value: sp ? pr : (pr >= 1 ? 1 : 0),
                                        minHeight: 3,
                                        backgroundColor: cs.primary.withValues(
                                          alpha: 0.12,
                                        ),
                                        color: cs.primary,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  borderRadius: BorderRadius.circular(6),
                                  onTap: () => TtsService.I.toggle(s.text),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    child: Text(
                                      sp ? '暂停' : '朗读',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: cs.primary,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 本地朗读本句（原版录音区间播放已移除：无法精准识别句子位置）
                    IconButton(
                      tooltip: TtsService.I.speaking.value ? '暂停朗读' : '朗读本句',
                      visualDensity: VisualDensity.compact,
                      iconSize: 20,
                      onPressed: () => TtsService.I.toggle(s.text),
                      icon: ValueListenableBuilder<bool>(
                        valueListenable: TtsService.I.speaking,
                        builder: (context, sp, _) => Icon(
                          sp
                              ? Icons.pause_circle_rounded
                              : Icons.record_voice_over_rounded,
                          color: sp ? cs.primary : cs.outline,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
