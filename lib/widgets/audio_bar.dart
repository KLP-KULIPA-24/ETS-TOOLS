import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/audio_player_service.dart';
import '../services/media_share.dart';
import 'speed_sheet.dart';

/// 音频播放条：播放/暂停、进度、倍速、AB 循环
class AudioBar extends StatefulWidget {
  final String source;
  final String title;
  final double? from;
  final double? to;
  final bool showAbLoop;
  final bool compact;

  /// 保存/分享时的文件名（套卷名-题型-题目-原名）；null 用原文件名
  final String? targetName;

  const AudioBar({
    super.key,
    required this.source,
    this.title = '音频',
    this.from,
    this.to,
    this.showAbLoop = true,
    this.compact = false,
    this.targetName,
  });

  @override
  State<AudioBar> createState() => _AudioBarState();
}

class _AudioBarState extends State<AudioBar> {
  Timer? _ticker;
  double _pos = 0;
  double _dur = 0;

  // 拖动中的临时位置：不为空时优先于 _pos。
  // 否则每 200ms 的播放器回传会把手势顶回原位（表现就是"拖不动"）
  double? _dragPos;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      final ps = AudioPlayerService.I;
      if (ps.currentSource == widget.source) {
        setState(() {
          _pos = ps.position.inMilliseconds / 1000.0;
          _dur = ps.duration.inMilliseconds / 1000.0;
        });
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  bool get _isCurrent => AudioPlayerService.I.currentSource == widget.source;

  String _fmt(double s) {
    if (s <= 0) return '0:00';
    final m = s ~/ 60;
    final sec = (s % 60).round();
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Consumer<AudioPlayerService>(
      builder: (context, ps, _) {
        final active = _isCurrent;
        final isPlaying = active && ps.playing;
        final speed = ps.speed;
        final inLoop = active && ps.loopA != null;
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 10 : 14,
            vertical: widget.compact ? 6 : 10,
          ),
          decoration: BoxDecoration(
            color: active
                ? cs.primaryContainer.withValues(alpha: 0.35)
                : cs.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: () async {
                      if (!active) {
                        await ps.open(
                          widget.source,
                          from: widget.from,
                          to: widget.to,
                        );
                      } else {
                        await ps.toggle();
                      }
                      if (mounted) setState(() {});
                    },
                    icon: Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 10,
                            ),
                          ),
                          child: Slider(
                            // 拖动期间用本地拖动态，松手再交回播放器的真实位置
                            value: active && _dur > 0
                                ? (_dragPos ?? _pos).clamp(0, _dur)
                                : 0,
                            max: _dur > 0 ? _dur : 1,
                            onChanged: active && _dur > 0
                                ? (v) {
                                    setState(() => _dragPos = v);
                                    ps.seek(v);
                                  }
                                : null,
                            onChangeEnd: active && _dur > 0
                                ? (v) {
                                    ps.seek(v);
                                    if (mounted) setState(() => _dragPos = null);
                                  }
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${_fmt(_pos)} / ${_fmt(_dur)}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Spacer(),
                  // 倍速：点开面板（预设档 + 滑杆拖动 + 手动输入任意值）
                  Tooltip(
                    message: '播放倍速',
                    child: ActionChip(
                      avatar: Icon(
                        Icons.speed_rounded,
                        size: 16,
                        color: cs.primary,
                      ),
                      label: Text(
                        '${speed}x',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () async {
                        final r = await showSpeedSheet(
                          context,
                          current: ps.speed,
                        );
                        if (r != null) {
                          ps.setSpeed(r);
                          if (mounted) setState(() {});
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (widget.showAbLoop)
                    Tooltip(
                      message: 'A-B 逐句循环：先设A点，再设B点',
                      child: IconButton(
                        isSelected: inLoop,
                        onPressed: () {
                          if (!active) return;
                          if (ps.loopA == null) {
                            ps.setLoop(_pos, null);
                            _snack(context, '已设 A 点 $_pos s，再次点击设 B 点');
                          } else if (ps.loopB == null) {
                            ps.setLoop(ps.loopA, _pos);
                          } else {
                            ps.setLoop(null, null);
                          }
                        },
                        icon: const Icon(Icons.repeat_rounded),
                      ),
                    ),
                  if (!widget.source.startsWith('http'))
                    IconButton(
                      tooltip: '保存 / 分享',
                      onPressed: () => MediaShare.showSheet(
                        context,
                        widget.source,
                        title: widget.title.isEmpty ? '录音' : widget.title,
                        targetName: widget.targetName,
                      ),
                      icon: const Icon(Icons.ios_share_rounded),
                    ),
                  IconButton(
                    tooltip: '回退5秒',
                    onPressed: active
                        ? () => ps.seek((_pos - 5).clamp(0, _dur))
                        : null,
                    icon: const Icon(Icons.replay_5_rounded),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 1)),
      );
  }
}
