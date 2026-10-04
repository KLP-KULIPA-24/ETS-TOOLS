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
        final active = ps.currentSource == widget.source;
        final btn = IconButton(
          tooltip: widget.tip,
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          onPressed: () {
            if (!active) {
              ps.open(widget.source);
            } else {
              ps.toggle();
            }
          },
          icon: Icon(
            active && ps.playing
                ? Icons.pause_circle_rounded
                : widget.icon,
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
              width: 56,
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: cur / total,
                      minHeight: 3,
                      backgroundColor: cs.primary.withValues(alpha: 0.15),
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
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