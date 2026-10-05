import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/ets_models.dart';
import '../services/audio_player_service.dart';

/// 跟读高亮文本：播放原文/范文录音时，已读过的句子染成主题色、
/// 当前句加粗高亮、后面的保持原色；全文始终完整显示。
/// 可在「设置 → 外观 → 跟读高亮」关闭（enabled=false 时纯文本）。
/// 时间轴来源：
/// - 逐句时间轴（朗读 videotime / 对话 sublist）→ 精确到句
/// - 无时间轴（标准范文）→ 按字数比例把音频时长平均分配给各句
class KtvText extends StatefulWidget {
  final List<SentenceSeg> segments;
  final String audioFile; // 正在播放的音频路径（用于监听进度）
  final TextStyle baseStyle;
  final bool selectable;
  final bool enabled; // 关闭时只显示全文，不做逐句染色
  /// 划词菜单（朗读/释义/复制）；null 用默认菜单
  final Widget Function(BuildContext, EditableTextState)? menuBuilder;

  /// 无时间轴时：按 [text] 分句 + [durationSec] 比例分配（范文/正文）。
  /// 传了 segments 则忽略这两项。
  final String? text;
  final double durationSec;

  const KtvText({
    super.key,
    this.segments = const [],
    required this.audioFile,
    this.baseStyle = const TextStyle(height: 1.7, fontSize: 15),
    this.selectable = false,
    this.enabled = true,
    this.menuBuilder,
    this.text,
    this.durationSec = 0,
  });

  @override
  State<KtvText> createState() => _KtvTextState();
}

class _KtvTextState extends State<KtvText> {
  Timer? _ticker;
  int _active = -1; // 当前句索引；-1 = 未播放
  // 估算分句（无显式时间轴）实际使用的分句与时长：
  // 时长未从外部传入时直接取播放器元数据，让所有录音都无需额外接线
  List<SentenceSeg> _segs = const [];
  double _psDur = 0;

  void _recomputeSegs(double dur) {
    if (widget.segments.isNotEmpty) {
      _segs = widget.segments;
      return;
    }
    _segs = (widget.text != null && dur > 0)
        ? sentencesByProportion(widget.text!, dur)
        : const <SentenceSeg>[];
  }

  @override
  void initState() {
    super.initState();
    _recomputeSegs(widget.durationSec);
    _ticker = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (!mounted) return;
      final ps = AudioPlayerService.I;
      // 路径全等或同文件名都算命中（不同来源的路径分隔符/前缀差异）
      final src = ps.currentSource;
      final match =
          widget.audioFile.isNotEmpty &&
          (src == widget.audioFile ||
              (src.isNotEmpty &&
                  p.basename(src) == p.basename(widget.audioFile)));
      if (!match) {
        if (_active != -1) setState(() => _active = -1);
        return;
      }
      // 无显式时间轴：时长直接取播放器元数据（元数据就绪后分句重建一次）
      if (widget.segments.isEmpty && widget.durationSec <= 0) {
        final d = ps.duration.inMilliseconds / 1000.0;
        if ((d - _psDur).abs() > 0.05) {
          _psDur = d;
          _recomputeSegs(_psDur);
          if (mounted) setState(() {});
        }
      }
      final pos = ps.position.inMilliseconds / 1000.0;
      final idx = _indexAt(pos);
      if (idx != _active) setState(() => _active = idx);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// 当前播放位置对应的句子索引
  int _indexAt(double pos) {
    final segs = _segs;
    for (var i = 0; i < segs.length; i++) {
      if (pos >= segs[i].begin && pos < segs[i].end) return i;
    }
    // 落在所有时间轴之外：已播完则停在最后一句，否则未开始
    if (segs.isNotEmpty && pos > segs.last.end) return segs.length - 1;
    return -1;
  }

  /// 完整原文（清洗 HTML + 空白归一）
  String _plain() {
    final src = widget.text != null
        ? widget.text!
        : widget.segments.map((s) => s.text).join(' ');
    return src
        .replaceAll(RegExp(r'</p>\s*<p>'), '. ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceFirst(RegExp(r'^\.\s*'), ''); // 段首 </p><p> 替换留下的前导句点
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = widget.baseStyle;
    if (!widget.enabled) {
      // 跟读高亮关闭：完整原文纯文本（仍支持划词菜单）
      final plain0 = _plain();
      if (widget.selectable) {
        return SelectableText(
          plain0,
          style: base,
          contextMenuBuilder: widget.menuBuilder,
        );
      }
      return RichText(
        text: TextSpan(text: plain0, style: base),
      );
    }
    // 句子来源：显式时间轴优先；否则按文本分句 + 时长比例分配
    _recomputeSegs(widget.durationSec > 0 ? widget.durationSec : _psDur);
    final segs = _segs;
    // 完整原文底稿（所有文字与标点都在）——高亮只在其中染色，绝不丢字
    final plain = _plain();
    // 按句在原文里顺序定位 → 染色区间；匹配不到的句子跳过（文字仍在原文里）
    final paint = <int, int>{}; // 断点 -> 染色类型（1 已读 / 2 当前句）
    var cursor = 0;
    for (var i = 0; i < segs.length; i++) {
      final st = segs[i].text.trim();
      if (st.isEmpty) continue;
      final at = plain.indexOf(st, cursor);
      if (at < 0) continue;
      final kind = i < _active ? 1 : (i == _active ? 2 : 0);
      paint[at] = kind;
      paint[at + st.length] = kind;
      cursor = at + st.length;
    }
    final points = paint.keys.toList()..sort();
    final spans = <InlineSpan>[];
    var pos = 0;
    for (var k = 0; k < points.length; k++) {
      final p = points[k];
      if (p > pos) {
        spans.add(TextSpan(text: plain.substring(pos, p), style: base));
      }
      final kind = paint[p]!;
      final end2 = (k + 1 < points.length) ? points[k + 1] : plain.length;
      final style = kind == 1
          ? base.copyWith(color: cs.primary) // 已读
          : kind == 2
          ? base.copyWith(color: cs.primary, fontWeight: FontWeight.w700) // 当前句
          : base; // 未读
      spans.add(TextSpan(text: plain.substring(p, end2), style: style));
      pos = end2;
    }
    if (pos < plain.length) {
      spans.add(TextSpan(text: plain.substring(pos), style: base));
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(text: plain, style: base));
    }
    if (!widget.selectable) {
      return RichText(
        text: TextSpan(children: spans),
        textAlign: TextAlign.start,
      );
    }
    // 可选词：走 SelectableText.rich 以挂自定义划词菜单（朗读/释义/复制）
    return SelectableText.rich(
      TextSpan(children: spans),
      contextMenuBuilder: widget.menuBuilder,
      textAlign: TextAlign.start,
    );
  }
}

/// 把无时间轴的纯文本（标准范文/故事正文）按句切分，并按字数比例分配时间轴。
/// [durationSec] 取自实际音频长度。
List<SentenceSeg> sentencesByProportion(String text, double durationSec) {
  final raw = text
      .replaceAll(RegExp(r'</p>\s*<p>'), '. ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (raw.isEmpty) return const [];
  final parts = raw
      .split(RegExp(r'(?<=[.!?;])\s+'))
      .where((x) => x.trim().isNotEmpty)
      .toList();
  if (parts.isEmpty) return const [];
  final totalChars = parts.fold<int>(0, (a, p) => a + p.length);
  if (totalChars == 0) return const [];
  final out = <SentenceSeg>[];
  var t = 0.0;
  for (var i = 0; i < parts.length; i++) {
    final share = parts[i].length / totalChars * durationSec;
    out.add(
      SentenceSeg(
        seq: '${i + 1}',
        text: parts[i],
        ai: '',
        translate: '',
        role: '',
        begin: t,
        end: i == parts.length - 1 ? durationSec : t + share,
      ),
    );
    t += share;
  }
  return out;
}
