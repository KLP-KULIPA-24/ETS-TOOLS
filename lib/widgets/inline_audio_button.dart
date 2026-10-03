import 'dart:io';

import 'package:flutter/material.dart';

import '../services/audio_player_service.dart';

/// 行内音频按钮：点击播放/暂停。
/// 注意：**不在行内展开控制条**——紧凑行（三问卡首行等）里展开会挤压
/// 相邻文字（曾把问句挤成竖排）。播放的进度/倍速/暂停由全局底部播放条
/// （MiniPlayer，任何页面常驻）承担；有空间的场景（范文/材料区）
/// 直接用 AudioBar。
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
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 文件不存在时直接隐藏，避免点击无效
    if (widget.source.isEmpty || !File(widget.source).existsSync()) {
      return const SizedBox.shrink();
    }
    final ps = AudioPlayerService.I;
    final active = ps.currentSource == widget.source;
    return ListenableBuilder(
      listenable: ps,
      builder: (context, _) => IconButton(
        tooltip: widget.tip,
        visualDensity: VisualDensity.compact,
        iconSize: 20,
        onPressed: () {
          if (!active) {
            ps.open(widget.source);
          } else {
            ps.toggle();
          }
        },
        icon: Icon(
          active && ps.playing ? Icons.pause_circle_rounded : widget.icon,
          color: active ? cs.primary : null,
        ),
      ),
    );
  }
}
