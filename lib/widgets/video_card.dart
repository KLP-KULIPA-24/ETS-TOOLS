/// 本地视频播放卡（media_kit 全平台：模仿朗读 content.mp4 等）
/// - **自绘控制条**（进度条/时间/播放/倍速/全屏）：手机端原生控件的细进度条太难点，
///   双端统一用这一套
/// - 倍速面板：预设档 + 滑杆 + 手动输入（见 speed_sheet.dart）
/// - 与音频播放器互斥：开播先停音频，音频开播则暂停视频，保证同一时刻只有一个在发声
library;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../services/audio_player_service.dart';
import '../services/media_share.dart';
import 'speed_sheet.dart';

class VideoCard extends StatefulWidget {
  final String source; // 文件绝对路径
  final String title;
  final bool autoPlay; // 模拟考场流程里进入即播
  /// 保存/分享文件名（套卷名-题型-原名）
  final String? targetName;
  const VideoCard({
    super.key,
    required this.source,
    this.title = '',
    this.autoPlay = false,
    this.targetName,
  });

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  bool _loaded = false;
  VoidCallback? _audioWatch;
  Duration _dur = Duration.zero; // 媒体时长（元数据就绪后回填）
  double? _dragPos; // 拖动中的位置（秒），null = 跟随播放进度
  bool _showBar = true; // 控制条常显；点画面可收起/展开

  @override
  void initState() {
    super.initState();
    // 音频开播 → 暂停视频（互斥）
    _audioWatch = () {
      if (AudioPlayerService.I.playing && _player.state.playing) {
        _player.pause();
      }
    };
    AudioPlayerService.I.addListener(_audioWatch!);
    if (widget.autoPlay) {
      _loaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _player.open(Media(widget.source));
      });
    }
  }

  @override
  void dispose() {
    if (_audioWatch != null) AudioPlayerService.I.removeListener(_audioWatch!);
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (!_loaded) {
      // 视频开播前先停音频（互斥）
      await AudioPlayerService.I.stop();
      setState(() {
        _loaded = true;
        _showBar = true;
      });
      await _player.open(Media(widget.source));
      return;
    }
    await _player.playOrPause();
  }

  Future<void> _pickSpeed() async {
    final r = await showSpeedSheet(context, current: _player.state.rate);
    if (r != null) await _player.setRate(r);
  }


  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(Icons.videocam_rounded, size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ),
                // 视频下载/分享（另存为、系统分享、复制路径）
                IconButton(
                  tooltip: '下载 / 分享',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed: () => MediaShare.showSheet(
                    context,
                    widget.source,
                    title: '考试视频',
                  ),
                  icon: const Icon(Icons.ios_share_rounded),
                ),
              ],
            ),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 只出画面，控件全部自绘（双端一致）
                  Video(controller: _controller, controls: NoVideoControls()),
                  // 点画面：播放/暂停；同时把控制条收起来
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (!_loaded) {
                        _toggle();
                        return;
                      }
                      _toggle();
                      setState(() => _showBar = !_showBar);
                    },
                  ),
                  // 中央播放钮（未播时）
                  StreamBuilder<bool>(
                    stream: _player.stream.playing,
                    initialData: false,
                    builder: (context, snap) {
                      final playing = snap.data ?? false;
                      if (_loaded && playing) return const SizedBox.shrink();
                      return Center(
                        child: IconButton.filled(
                          iconSize: 54,
                          tooltip: '播放视频',
                          onPressed: _toggle,
                          style: IconButton.styleFrom(
                            backgroundColor: cs.primary.withValues(alpha: 0.9),
                            foregroundColor: cs.onPrimary,
                          ),
                          icon: const Icon(Icons.play_arrow_rounded),
                        ),
                      );
                    },
                  ),
                  // 底部自绘控制条
                  if (_showBar)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _VideoBar(
                        player: _player,
                        loaded: _loaded,
                        dur: _dur,
                        dragPos: _dragPos,
                        onDragStart: (v) => setState(() => _dragPos = v),
                        onDragUpdate: (v) => setState(() => _dragPos = v),
                        onDragEnd: (v) {
                          setState(() => _dragPos = null);
                          _player.seek(Duration(milliseconds: (v * 1000).round()));
                        },
                        onToggle: _toggle,
                        onSpeed: _pickSpeed,
                        onDuration: (d) {
                          if (d > Duration.zero && d != _dur) {
                            setState(() => _dur = d);
                          }
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 自绘底部控制条：播放 / 时间 / 粗进度条 / 倍速 / 全屏（手机电脑同一套）
class _VideoBar extends StatelessWidget {
  final Player player;
  final bool loaded;
  final Duration dur;
  final double? dragPos;
  final void Function(double) onDragStart;
  final void Function(double) onDragUpdate;
  final void Function(double) onDragEnd;
  final VoidCallback onToggle;
  final VoidCallback onSpeed;
  final void Function(Duration) onDuration;

  const _VideoBar({
    required this.player,
    required this.loaded,
    required this.dur,
    required this.dragPos,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onToggle,
    required this.onSpeed,
    required this.onDuration,
  });

  static String _hms(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<Duration?>(
      stream: player.stream.duration,
      initialData: null,
      builder: (context, durSnap) {
        final d = durSnap.data ?? dur;
        if (d != dur) onDuration(d);
        return StreamBuilder<Duration>(
          stream: player.stream.position,
          initialData: Duration.zero,
          builder: (context, posSnap) {
            final pos = dragPos ?? posSnap.data!.inMilliseconds / 1000.0;
            final total = d.inMilliseconds > 0 ? d.inMilliseconds / 1000.0 : 0.0;
            final cur = pos.clamp(0.0, total > 0 ? total : 0.0);
            return Container(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0),
                    Colors.black.withValues(alpha: 0.55),
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 进度条：轨道加粗 + 大拇指，手机上好按
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 5,
                      activeTrackColor: cs.primary,
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.28),
                      thumbColor: cs.primary,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 16,
                      ),
                      overlayColor: cs.primary.withValues(alpha: 0.18),
                    ),
                    child: Slider(
                      value: cur,
                      max: total > 0 ? total : 1.0,
                      onChanged: loaded && total > 0 ? onDragUpdate : null,
                      onChangeStart: loaded && total > 0 ? onDragStart : null,
                      onChangeEnd: loaded && total > 0 ? onDragEnd : null,
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        tooltip: '播放 / 暂停',
                        visualDensity: VisualDensity.compact,
                        color: Colors.white,
                        onPressed: onToggle,
                        icon: StreamBuilder<bool>(
                          stream: player.stream.playing,
                          initialData: false,
                          builder: (context, s) => Icon(
                            (s.data ?? false)
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 22,
                          ),
                        ),
                      ),
                      Text(
                        '${_hms(Duration(milliseconds: (cur * 1000).round()))}'
                        ' / ${_hms(d)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      StreamBuilder<double>(
                        stream: player.stream.rate,
                        initialData: 1.0,
                        builder: (context, r) => TextButton(
                          onPressed: onSpeed,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(44, 36),
                          ),
                          child: Text(
                            '${(r.data ?? 1.0).toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')}x',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '全屏',
                        visualDensity: VisualDensity.compact,
                        color: Colors.white,
                        onPressed: () {},
                        icon: const Icon(Icons.fullscreen_rounded, size: 20),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}