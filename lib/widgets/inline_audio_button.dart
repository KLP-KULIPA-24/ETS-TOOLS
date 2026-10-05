import 'dart:io';

import 'package:flutter/material.dart';

import '../services/audio_player_service.dart';

/// 行内音频按钮：点击播放/暂停，**本条正在播时按钮下方展开一条细进度条 + 时间**。
/// 只展开"当前正在播"的那一条，不会把整列表撑开（旧版在行内展开完整控制条，
/// 曾把三问卡的问句挤成竖排）。
class InlineAudioButton extends StatefulWidget {
  final String source; // 文件绝对路径
  final String tip;
  final IconData icon;
  const InlineAudioButton({
    super.key,
    required this.source,
    this.tip = '播放录音',
    this.icon = Icons.volume_up_rounded,
  });

  @override
  State<InlineAudioButton> createState() => _InlineAudioButtonState();
}

class _InlineAudioButtonState extends State<InlineAudioButton> {
  static int _seq = 0;
  // 实例身份：同一份录音被多道题引用时，只有发起播放的那个按钮高亮
  late final int _owner = ++_seq;

  // 拖动中的临时位置：不为空时优先于流里的 position，
  // 否则 seek 引发的流更新会把手势打回原位（表现就是"拖不动"）
  double? _dragPos;

  static String _hms(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 文件不存在时直接隐藏，避免点击无效
    if (widget.source.isEmpty || !File(widget.source).existsSync()) {
      return const SizedBox.shrink();
    }
    final ps = AudioPlayerService.I;
    return ListenableBuilder(
      listenable: ps,
      builder: (context, _) {
        final active = ps.activeOwner == _owner;
        final btn = IconButton(
          tooltip: widget.tip,
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          onPressed: () {
            if (!active) {
              ps.open(widget.source, owner: _owner);
            } else {
              ps.toggle();
            }
          },
          icon: Icon(
            active && ps.playing ? Icons.pause_circle_rounded : widget.icon,
            color: active ? cs.primary : null,
          ),
        );
        if (!active) return btn;
        // 正在播本条：按钮下方展开细进度条
        final dur = ps.duration;
        final pos = ps.position;
        final total = dur.inMilliseconds > 0 ? dur.inMilliseconds : 1;
        final cur = pos.inMilliseconds.clamp(0, total);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            btn,
            SizedBox(
              width: 96,
              child: Column(
                children: [
                  // 可拖动的进度条：之前是只读 LinearProgressIndicator，
                  // 用户拖不动（反馈"进度条无法拖动"）
                  SizedBox(
                    height: 24,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        activeTrackColor: cs.primary,
                        inactiveTrackColor: cs.primary.withValues(alpha: 0.15),
                        thumbColor: cs.primary,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 5,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 14,
                        ),
                        overlayColor: cs.primary.withValues(alpha: 0.18),
                      ),
                      child: Slider(
                        // 拖动期间用本地临时值，松手才交回播放器的真实位置
                        value: (_dragPos ?? cur.toDouble()).clamp(
                          0,
                          total.toDouble(),
                        ),
                        max: total.toDouble(),
                        onChanged: (v) {
                          setState(() => _dragPos = v);
                          AudioPlayerService.I.seek(v);
                        },
                        onChangeEnd: (v) {
                          AudioPlayerService.I.seek(v);
                          if (mounted) setState(() => _dragPos = null);
                        },
                      ),
                    ),
                  ),
                  Text(
                    '${_hms(pos)}/${_hms(dur)}',
                    style: TextStyle(fontSize: 12, color: cs.outline),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
