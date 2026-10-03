/// 本地视频播放卡（media_kit 全平台：模仿朗读 content.mp4 等）
/// - 使用播放器原生控件（进度条 / 拖动 / 暂停 / 全屏）
/// - 与音频播放器互斥：开播先停音频，音频开播则暂停视频，保证同一时刻只有一个在发声
library;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../services/audio_player_service.dart';
import '../services/media_share.dart';

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
      _loaded = true;
      await _player.open(Media(widget.source));
      return;
    }
    await _player.playOrPause();
  }

  static const _rates = [0.6, 0.8, 1.0, 1.25, 1.5, 2.0];

  void _showSpeedMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            for (final r in _rates)
              ListTile(
                dense: true,
                leading: r == _player.state.rate
                    ? Icon(
                        Icons.check_rounded,
                        color: Theme.of(ctx).colorScheme.primary,
                      )
                    : const SizedBox(width: 24),
                title: Text('${r}x'),
                onTap: () {
                  _player.setRate(r);
                  Navigator.of(ctx).pop();
                },
              ),
          ],
        ),
      ),
    );
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
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    // 原生控件；进度条/滑块用主题色，底部按钮栏加视频倍速
                    child: MaterialVideoControlsTheme(
                      normal: MaterialVideoControlsThemeData(
                        seekBarPositionColor: cs.primary,
                        seekBarThumbColor: cs.primary,
                        seekBarHeight: 4,
                        bottomButtonBar: [
                          MaterialCustomButton(
                            onPressed: () => _showSpeedMenu(context),
                            icon: const Icon(Icons.speed_rounded),
                          ),
                          const Spacer(),
                          const MaterialFullscreenButton(),
                        ],
                      ),
                      fullscreen: MaterialVideoControlsThemeData(
                        seekBarPositionColor: cs.primary,
                        seekBarThumbColor: cs.primary,
                        seekBarHeight: 5,
                        bottomButtonBar: [
                          MaterialCustomButton(
                            onPressed: () => _showSpeedMenu(context),
                            icon: const Icon(Icons.speed_rounded),
                          ),
                          const Spacer(),
                          const MaterialFullscreenButton(),
                        ],
                      ),
                      child: Video(controller: _controller),
                    ),
                  ),
                  // 未开始时的中央播放钮（开播后隐藏，交给原生控件）
                  StreamBuilder<bool>(
                    stream: _player.stream.playing,
                    initialData: false,
                    builder: (context, snap) {
                      final playing = snap.data ?? false;
                      if (_loaded && playing) return const SizedBox.shrink();
                      return IconButton.filledTonal(
                        iconSize: 56,
                        tooltip: '播放视频',
                        onPressed: _toggle,
                        icon: Icon(
                          Icons.play_circle_rounded,
                          color: cs.primary,
                        ),
                      );
                    },
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
