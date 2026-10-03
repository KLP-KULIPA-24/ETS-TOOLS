import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/audio_player_service.dart';
import 'glass.dart';

/// 全局迷你播放条：任何位置点了播放都从这里统一控制
/// —— 播放/暂停、进度拖动、关闭；离开详情页返回上层时依然可控
class MiniPlayer extends StatefulWidget {
  final double bottomOffset; // 避让底部悬浮胶囊 / 安全区
  const MiniPlayer({super.key, this.bottomOffset = 16});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  Timer? _ticker;
  final _dragValue = ValueNotifier<double?>(null);

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _dragValue.dispose();
    super.dispose();
  }

  String _fmt(double s) {
    s = s.clamp(0, 1e6);
    final m = (s ~/ 60).toInt();
    final r = (s % 60).floor();
    return '$m:${r < 10 ? '0' : ''}$r';
  }

  @override
  Widget build(BuildContext context) {
    final ps = AudioPlayerService.I;
    final src = ps.currentSource;
    if (src.isEmpty || ps.duration <= Duration.zero) {
      return const SizedBox.shrink();
    }
    final cs = Theme.of(context).colorScheme;
    final dur = ps.duration.inMilliseconds / 1000.0;
    final pos = ps.position.inMilliseconds / 1000.0;
    final name = p.basenameWithoutExtension(src);
    final dragging = _dragValue.value;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, widget.bottomOffset),
      child: GlassContainer(
        radius: 18,
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  ps.playing ? Icons.graphic_eq_rounded : Icons.pause_rounded,
                  size: 20,
                  color: cs.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${_fmt(dragging ?? pos)} / ${_fmt(dur)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.outline,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                IconButton(
                  tooltip: ps.playing ? '暂停' : '继续播放',
                  visualDensity: VisualDensity.compact,
                  onPressed: ps.toggle,
                  icon: Icon(
                    ps.playing
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded,
                    size: 26,
                    color: cs.primary,
                  ),
                ),
                IconButton(
                  tooltip: '关闭播放',
                  visualDensity: VisualDensity.compact,
                  onPressed: ps.stop,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
            // 进度条：拖动即 seek
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: cs.primary,
                inactiveTrackColor: cs.primary.withValues(alpha: 0.18),
                thumbColor: cs.primary,
              ),
              child: Slider(
                value: (dragging ?? pos).clamp(0, dur),
                max: dur <= 0 ? 1 : dur,
                onChanged: (v) => _dragValue.value = v,
                onChangeEnd: (v) {
                  ps.seek(v);
                  _dragValue.value = null;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
