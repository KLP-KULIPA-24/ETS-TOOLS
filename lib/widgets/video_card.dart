/// 本地视频播放卡（双后端：Windows = media_kit；Android = 官方 video_player）
/// - **自绘控制条**（进度条/时间/播放/倍速/全屏）：手机端原生控件的细进度条太难点，
///   双端统一用这一套
/// - 倍速面板：预设档 + 滑杆 + 手动输入（见 speed_sheet.dart）
/// - 与音频播放器互斥：开播先停音频，音频开播则暂停视频，保证同一时刻只有一个在发声
///
/// 为什么 Android 不用 media_kit：libmpv 的 GL 渲染在部分 GPU/模拟器上初始化
/// 10-bit 中间纹理（logcat: `Failed to initialize 101010-2 format`）失败，失败后
/// 整帧只剩红通道（G/B 全丢，用户连报"视频是红色"）。软解/硬解、vf 强转 RGBA、
/// gpu-dumb-mode 全都绕不过——这是驱动层的 FBO 缺陷。ExoPlayer +
/// SurfaceTexture 是系统级渲染管线，颜色必然正确，故 Android 改用官方
/// video_player；Windows 上 media_kit 表现正常，维持原实现。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player/video_player.dart';

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
    required this.title,
    this.autoPlay = false,
    this.targetName,
  });

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  late final _Core _core = Platform.isWindows ? _MkCore() : _VpCore();
  bool _loaded = false;
  bool _showBar = true;

  @override
  void initState() {
    super.initState();
    // 音频开播 → 暂停视频（互斥）
    _audioWatch = () {
      if (AudioPlayerService.I.playing && _core.playing) {
        _core.pause();
      }
    };
    AudioPlayerService.I.addListener(_audioWatch!);
    if (widget.autoPlay) {
      _loaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _core.open(widget.source);
      });
    }
  }

  VoidCallback? _audioWatch;

  @override
  void dispose() {
    if (_audioWatch != null) AudioPlayerService.I.removeListener(_audioWatch!);
    _core.dispose();
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
      await _core.open(widget.source);
      return;
    }
    await _core.toggle();
  }

  /// 真全屏：同一播放核心的画面推到全屏路由，控制条照旧
  void _openFullscreen() {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (routeC, a, _) => _FullscreenVideo(
          core: _core,
          onClose: () => Navigator.of(routeC).pop(),
          onToggle: _toggle,
          onSpeed: _pickSpeed,
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  Future<void> _pickSpeed() async {
    final r = await showSpeedSheet(context, current: _core.rate);
    if (r != null) await _core.setRate(r);
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
                    targetName: widget.targetName,
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
                  // 只出画面，控件全部自绘（双端一致）。
                  // 画面必须跟着播放核心重建：初始化完成前 video() 是黑底
                  // 占位，若不随 notifyListeners 重建，首帧要等手动拖进度条
                  // 触发 setState 才会出现（黑屏问题）。
                  AnimatedBuilder(animation: _core, builder: (_, _) => _core.video()),
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
                  AnimatedBuilder(
                    animation: _core,
                    builder: (context, _) {
                      if (_loaded && _core.playing) {
                        return const SizedBox.shrink();
                      }
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
                        core: _core,
                        loaded: _loaded,
                        dragPos: _dragPos,
                        onDragStart: (v) => setState(() => _dragPos = v),
                        onDragUpdate: (v) => setState(() => _dragPos = v),
                        onDragEnd: (v) {
                          setState(() => _dragPos = null);
                          _core.seek(v);
                        },
                        onToggle: _toggle,
                        onSpeed: _pickSpeed,
                        onFullscreen: _openFullscreen,
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

  double? _dragPos;
}

/// 播放核心抽象：VideoCard 的 UI 只认它，不关心底下是 media_kit 还是 ExoPlayer。
abstract class _Core extends ChangeNotifier {
  bool playing = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  double rate = 1.0;

  Future<void> open(String src);
  Future<void> toggle();
  Future<void> pause();
  Future<void> seek(double sec);
  Future<void> setRate(double r);

  /// 画面 widget（铺满父级使用）
  Widget video();

  @override
  void dispose();
}

/// Windows：media_kit（桌面表现稳定，历史实现）
class _MkCore extends _Core {
  final Player _player = Player();
  late final VideoController _controller = VideoController(
    _player,
    // 关闭 GPU 渲染：media_kit 文档明写"关闭可提升某些设备稳定性"
    configuration: const VideoControllerConfiguration(
      enableHardwareAcceleration: false,
    ),
  );

  _MkCore() {
    _player.stream.playing.listen((v) {
      playing = v;
      notifyListeners();
    });
    _player.stream.position.listen((v) {
      position = v;
      notifyListeners();
    });
    _player.stream.duration.listen((v) {
      duration = v;
      notifyListeners();
    });
    _player.stream.rate.listen((v) {
      rate = v;
      notifyListeners();
    });
  }

  @override
  Future<void> open(String src) =>
      _player.open(Media(src), play: true).then((_) {});

  @override
  Future<void> toggle() => _player.playOrPause();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(double sec) => _player.seek(
    Duration(milliseconds: (sec * 1000).round()),
  );

  @override
  Future<void> setRate(double r) => _player.setRate(r);

  @override
  Widget video() => Video(controller: _controller, controls: NoVideoControls);

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}

/// Android：官方 video_player（ExoPlayer + SurfaceTexture，颜色必然正确）
class _VpCore extends _Core {
  VideoPlayerController? _c;

  void _sync() {
    final v = _c?.value;
    if (v == null) return;
    playing = v.isPlaying;
    position = v.position;
    duration = v.duration;
    rate = v.playbackSpeed;
    notifyListeners();
  }

  @override
  Future<void> open(String src) async {
    final c = VideoPlayerController.file(File(src));
    _c = c;
    c.addListener(_sync);
    await c.initialize();
    notifyListeners();
    await c.play();
  }

  @override
  Future<void> toggle() async {
    final c = _c;
    if (c == null) return;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      await c.play();
    }
  }

  @override
  Future<void> pause() => _c?.pause() ?? Future.value();

  @override
  Future<void> seek(double sec) =>
      _c?.seekTo(Duration(milliseconds: (sec * 1000).round())) ??
      Future.value();

  @override
  Future<void> setRate(double r) => _c?.setPlaybackSpeed(r) ?? Future.value();

  @override
  Widget video() {
    final c = _c;
    if (c == null || !c.value.isInitialized) {
      return Container(color: Colors.black);
    }
    // 保持视频自身宽高比铺满卡内区域（卡外层已有 16:9 AspectRatio 兜底）
    return Center(
      child: AspectRatio(
        aspectRatio: c.value.aspectRatio,
        child: VideoPlayer(c),
      ),
    );
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }
}

/// 自绘底部控制条：播放 / 时间 / 粗进度条 / 倍速 / 全屏（手机电脑同一套）
class _VideoBar extends StatelessWidget {
  final _Core core;
  final bool loaded;
  final double? dragPos;
  final void Function(double) onDragStart;
  final void Function(double) onDragUpdate;
  final void Function(double) onDragEnd;
  final VoidCallback onToggle;
  final VoidCallback onSpeed;
  final VoidCallback onFullscreen;

  const _VideoBar({
    required this.core,
    required this.loaded,
    required this.dragPos,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onToggle,
    required this.onSpeed,
    required this.onFullscreen,
  });

  static String _hms(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: core,
      builder: (context, _) {
        final d = core.duration;
        final pos = dragPos ?? core.position.inMilliseconds / 1000.0;
        final total = d.inMilliseconds > 0
            ? d.inMilliseconds / 1000.0
            : 0.0;
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
                    icon: Icon(
                      core.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 22,
                    ),
                  ),
                  Text(
                    '${_hms(Duration(milliseconds: (cur * 1000).round()))}'
                    ' / ${_hms(d)}',
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: onSpeed,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(44, 36),
                    ),
                    child: Text(
                      '${core.rate.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')}x',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  IconButton(
                    tooltip: '全屏',
                    visualDensity: VisualDensity.compact,
                    color: Colors.white,
                    onPressed: onFullscreen,
                    icon: const Icon(Icons.fullscreen_rounded, size: 20),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 全屏播放页：黑色背景 + 同一播放核心的画面 + 自绘控制条
class _FullscreenVideo extends StatefulWidget {
  final _Core core;
  final VoidCallback onClose;
  final VoidCallback onToggle;
  final VoidCallback onSpeed;

  const _FullscreenVideo({
    required this.core,
    required this.onClose,
    required this.onToggle,
    required this.onSpeed,
  });

  @override
  State<_FullscreenVideo> createState() => _FullscreenVideoState();
}

class _FullscreenVideoState extends State<_FullscreenVideo> {
  double? _drag;
  bool _bar = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              widget.onToggle();
              setState(() => _bar = !_bar);
            },
          ),
          Positioned.fill(child: widget.core.video()),
          // 顶部：返回 + 标题
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    tooltip: '退出全屏',
                    color: Colors.white,
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          ),
          if (_bar)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _VideoBar(
                core: widget.core,
                loaded: true,
                dragPos: _drag,
                onDragStart: (v) => setState(() => _drag = v),
                onDragUpdate: (v) => setState(() => _drag = v),
                onDragEnd: (v) {
                  setState(() => _drag = null);
                  widget.core.seek(v);
                },
                onToggle: widget.onToggle,
                onSpeed: widget.onSpeed,
                onFullscreen: widget.onClose,
              ),
            ),
        ],
      ),
    );
  }
}
