import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../models/ets_models.dart';
import '../../pages/detail/typed_views.dart' show TypedContentView;
import '../../services/audio_player_service.dart';
import '../../services/ets_data_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/glass.dart';
import '../../widgets/common.dart';
import '../../widgets/ets_text.dart';
import '../../widgets/video_card.dart';
import '../../services/achievements.dart';
import '../../services/media_share.dart';

/// 模拟考场：按 ctrl 脚本时间线执行 播放 → 倒计时 → 录音 → 回放
/// 题目内容（含图片）全程常驻展示；录音前等待点击开始、
/// 回放结束后等待"下一步"，不再自动突跳。
class ExamSimPage extends StatefulWidget {
  final HomeworkEntry entry;
  const ExamSimPage({super.key, required this.entry});

  @override
  State<ExamSimPage> createState() => _ExamSimPageState();
}

enum _Phase {
  idle, // 待开始
  playing, // 音频/视频播放 / 内容展示
  waiting, // 准备倒计时
  recordReady, // 等待点击"开始录音"
  recording, // 录音中
  replay, // 录音回放中
  replayDone, // 回放结束，等待"下一步"
  awaitNext, // 音频/视频播完，等待"下一步"（不自动跳）
  done, // 全部完成
}

class _ExamSimPageState extends State<ExamSimPage> {
  List<ExamStep> _steps = [];
  final List<ExamStep> _history = [];
  int _idx = 0;
  _Phase _phase = _Phase.idle;
  int _countdown = 0;
  Timer? _timer;
  final AudioRecorder _recorder = AudioRecorder();
  String? _lastRecording;
  String _statusText = '';
  String _displayTitle = '';
  String _displayBody = '';
  int _recSeconds = 0;
  bool _showAnswerCard = false;
  String? _videoFile; // 考试视频（模仿朗读 content.mp4），常驻展示
  String? _videoStPrefix; // 视频所属部分（{{st1}}），跨部分清除

  /// 回放结束后的"下一步"信号（Completer 由 UI 按钮完成）
  Completer<bool>? _nextWaiter;

  HomeworkEntry get e => widget.entry;
  String get _contentDir =>
      e.content?.dir ?? (e.paper != null ? e.paper!.dir : '');
  String get _uidDir => p.dirname(_contentDir);

  @override
  void initState() {
    super.initState();
    Achievements.unlock('exam');
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSteps());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    AudioPlayerService.I.stop();
    super.dispose();
  }

  String _templateDir = '';
  Map<String, String> _templateInfo = {};
  bool _skipRequested = false;

  Future<void> _loadSteps() async {
    // Windows 布局：template_*/ctrl.json；Android 布局：哈希兄弟目录含 ctrl.json
    String? ctrlPath;
    try {
      for (final d in Directory(_uidDir).listSync()) {
        if (d is Directory) {
          final f = File(p.join(d.path, 'ctrl.json'));
          if (f.existsSync()) {
            ctrlPath = f.path;
            _templateDir = d.path;
            // 模板显示文本（code_id -> code_value）
            final list = loadJsonList(p.join(d.path, 'info.json')) ?? const [];
            _templateInfo = {
              for (final item in list.whereType<Map>())
                '${item['code_id']}': '${item['code_value']}',
            };
            break;
          }
        }
      }
      ctrlPath ??= File(p.join(_contentDir, 'paper.ctrl')).existsSync()
          ? p.join(_contentDir, 'paper.ctrl')
          : null;
    } catch (_) {}

    if (ctrlPath == null) {
      setState(() {
        _statusText = '未找到考试流程脚本（ctrl.json / paper.ctrl），无法模拟。';
      });
      return;
    }
    final steps = EtsDataService.parseCtrlSteps(ctrlPath);
    // 展开子题脚本（paper.ctrl 的 vari.item → 子目录 .ctrl）
    final expanded = <ExamStep>[];
    for (final s in steps) {
      if (s.type == 'vari.item') {
        final subPath = p.join(_contentDir, s.filename, '${s.filename}.ctrl');
        if (File(subPath).existsSync()) {
          expanded.addAll(EtsDataService.parseCtrlSteps(subPath));
          continue;
        }
      }
      expanded.add(s);
    }
    setState(() {
      _steps = expanded;
      _statusText = expanded.isEmpty ? '流程脚本为空' : '';
      _idx = 0;
      _phase = _Phase.idle;
    });
  }

  Future<void> _start() async {
    if (!await SettingsService.requestMic()) {
      setState(() => _statusText = '需要麦克风权限');
      return;
    }
    _runStep(0);
  }

  void _skip() {
    setState(() => _skipRequested = true);
    final w = _nextWaiter;
    if (w != null && !w.isCompleted) w.complete(false);
  }

  void _stopAll() {
    _timer?.cancel();
    _recorder.stop();
    AudioPlayerService.I.stop();
    final w = _nextWaiter;
    if (w != null && !w.isCompleted) w.complete(false);
    setState(() {
      _phase = _Phase.idle;
      _showAnswerCard = false;
    });
  }

  void _finish() {
    _timer?.cancel();
    setState(() {
      _phase = _Phase.done;
      _showAnswerCard = true;
      _statusText = '已完成！对照右侧答案复盘，历史中可回听录音。';
    });
  }

  /// 解析 ctrl 步骤引用的音频绝对路径
  String _resolveAudio(ExamStep s) {
    final candidates = <String>[
      // dirtype: content → 内容目录；templet → 模板目录
      if (s.dirType == 'content') p.join(_contentDir, 'material', s.filename),
      if (s.dirType == 'templet' && _templateDir.isNotEmpty)
        p.join(_templateDir, 'material', s.filename),
      p.join(_contentDir, 'material', s.filename),
      if (_templateDir.isNotEmpty) p.join(_templateDir, 'material', s.filename),
      p.join(_uidDir, 'material', s.filename),
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return '';
  }

  /// 当前题目配图（材料目录），无图返回空
  String get _examImage {
    final c = e.content;
    if (c == null || c.image.isEmpty) return '';
    final f = p.join(_contentDir, 'material', c.image);
    return File(f).existsSync() ? f : '';
  }

  /// 参考答案（录音结束后对照用）
  String get _referenceAnswer {
    final c = e.content;
    if (c == null) return '';
    return TypedContentView.plainAnswerText(c);
  }

  Future<void> _runStep(int i) async {
    if (i >= _steps.length) {
      _finish();
      return;
    }
    final s = _steps[i];
    _skipRequested = false;
    // 跨部分（{{st1}}→{{st2}}）清除上一部分的视频
    if (_videoFile != null &&
        _videoStPrefix != null &&
        s.subId.split('_').first != _videoStPrefix) {
      _videoFile = null;
    }
    _history.add(s);
    setState(() {
      _idx = i;
      _statusText = '';
    });

    switch (s.type) {
      case 'view.html':
        // 完整展示：模板提示 + 题干正文（图片在内容卡常驻展示）
        String text = '';
        for (final entry in s.htmlParams.entries) {
          final v =
              _templateInfo[entry.value] ??
              '${e.content?.info[entry.value] ?? ''}';
          if (v.isNotEmpty) text = text.isEmpty ? v : '$text\n$v';
        }
        final body = e.content == null || EtsText.clean(e.content!.text).isEmpty
            ? EtsText.clean(text)
            : EtsText.clean(text) +
                  (text.isEmpty ? '' : '\n\n') +
                  EtsText.clean(e.content!.text);
        setState(() {
          _phase = _Phase.playing;
          _displayTitle = s.hint;
          _displayBody = body;
        });
        await _wait(6.0); // 给足读题时间（可跳过）
        _next(i);
      case 'file.audio':
        setState(() => _phase = _Phase.playing);
        final file = _resolveAudio(s);
        if (file.isEmpty) {
          setState(() => _statusText = '音频缺失: ${s.filename}（跳过）');
          await _wait(0.5);
          _next(i);
          return;
        }
        final from = s.playFrom > 0 ? s.playFrom : 0.0;
        final to = s.playTo;
        final player = AudioPlayerService.I;
        await player.open(
          file,
          from: from > 0 ? from : null,
          to: to > 0 ? to : null,
        );
        if (to > from && to > 0) {
          await _wait(to - from + 0.5);
        } else {
          await _waitUntilPlayerDone(player);
        }
        player.pause(); // 播放一遍即停，不自动跳下一步
        if (!mounted) return;
        setState(() => _phase = _Phase.awaitNext);
        await _waitUserNext();
      case 'file.video':
        // 模仿朗读的考试视频：常驻展示并自动播放，看完点"下一步"
        final file = _resolveAudio(s);
        if (file.isEmpty) {
          setState(() => _statusText = '视频缺失: ${s.filename}（跳过）');
          await _wait(0.5);
          _next(i);
          return;
        }
        _videoFile = file;
        _videoStPrefix = s.subId.split('_').first;
        setState(() => _phase = _Phase.awaitNext);
        await _waitUserNext();
      case 'wait':
        setState(() => _phase = _Phase.waiting);
        // "准备好了"可提前结束倒计时
        final early = Completer<bool>();
        _nextWaiter = early;
        for (var t = s.playtime.toInt(); t > 0; t--) {
          if (!mounted) return;
          setState(() => _countdown = t);
          final ok = await _wait(1);
          if (!ok) break;
          if (early.isCompleted) break;
        }
        _nextWaiter = null;
        _next(i);
      case 'action.record':
        // 先等用户点"开始录音"（考试感：准备自己开口的节奏）
        setState(() => _phase = _Phase.recordReady);
        final ok = await _waitUserNext();
        if (!ok) return;
        if (!mounted) return;
        await _doRecord(s);
        _next(i);
      case 'user.audio':
        if (_lastRecording != null && File(_lastRecording!).existsSync()) {
          setState(() => _phase = _Phase.replay);
          final player = AudioPlayerService.I;
          await player.open(_lastRecording!);
          await _waitUntilPlayerDone(player);
          // 回放结束：显示参考答案对照，等待"下一步"（不自动突跳）
          if (!mounted) return;
          setState(() {
            _phase = _Phase.replayDone;
            _showAnswerCard = true;
          });
          await _waitUserNext();
        }
        _next(i);
      default:
        await _wait(1);
        _next(i);
    }
  }

  Future<void> _doRecord(ExamStep s) async {
    setState(() => _phase = _Phase.recording);
    final recDir = await _recordDir();
    final path = p.join(recDir, '${s.filename}.m4a');
    final limit = s.playtime > 0 ? s.playtime : 30.0;
    if (await _recorder.hasPermission()) {
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      _recSeconds = 0;
      // "说完了"提前结束：挂一个 waiter，UI 确认即跳出倒计时
      final stopWaiter = Completer<bool>();
      _nextWaiter = stopWaiter;
      for (var t = limit.toInt(); t > 0; t--) {
        if (!mounted) return;
        setState(() => _recSeconds = limit.toInt() - t + 1);
        final ok = await _wait(1);
        if (!ok) break;
        if (stopWaiter.isCompleted) break;
      }
      _nextWaiter = null;
      final stopped = await _recorder.stop();
      if (mounted) setState(() => _lastRecording = stopped);
    } else {
      setState(() => _statusText = '无麦克风权限，跳过录音');
      await _wait(limit);
    }
  }

  void _next(int i) {
    if (!mounted) return;
    _runStep(i + 1);
  }

  /// 等待用户点"下一步"（或跳过/停止中断）
  Future<bool> _waitUserNext() {
    final w = Completer<bool>();
    _nextWaiter = w;
    return w.future;
  }

  void _confirmNext() {
    final w = _nextWaiter;
    if (w != null && !w.isCompleted) w.complete(true);
  }

  Future<String> _recordDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'recordings'))
      ..createSync(recursive: true);
    return dir.path;
  }

  /// 可中断等待：返回 false 表示用户点了跳过
  Future<bool> _wait(double sec) async {
    var remain = sec;
    while (remain > 0) {
      if (!mounted) return false;
      if (_skipRequested) {
        _skipRequested = false;
        return false;
      }
      final step = remain > 0.1 ? 0.1 : remain;
      await Future.delayed(Duration(milliseconds: (step * 1000).round()));
      remain -= step;
    }
    return true;
  }

  Future<void> _waitUntilPlayerDone(dynamic player) async {
    while (player.playing && mounted && !_skipRequested) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    _skipRequested = false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassScaffold(
      appBar: AppBar(
        title: Text('模拟考场 · ${e.title}'),
        actions: [
          IconButton(
            tooltip: '跳过当前步骤',
            onPressed: _phase == _Phase.idle || _phase == _Phase.done
                ? null
                : _skip,
            icon: const Icon(Icons.skip_next_rounded),
          ),
          IconButton(
            tooltip: '停止',
            onPressed: _phase == _Phase.idle ? null : _stopAll,
            icon: const Icon(Icons.stop_circle_outlined),
          ),
        ],
      ),
      body: _steps.isEmpty
          ? Center(child: Text(_statusText))
          : Column(
              children: [
                // 进度
                LinearProgressIndicator(
                  value: _steps.isEmpty ? 0 : (_idx + 1) / _steps.length,
                  minHeight: 4,
                  color: cs.primary,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      _phaseChip(context, '步骤 ${_idx + 1}/${_steps.length}'),
                      const SizedBox(width: 8),
                      _phaseChip(context, switch (_phase) {
                        _Phase.idle => '待开始',
                        _Phase.playing => '播放中',
                        _Phase.waiting => '准备 $_countdown s',
                        _Phase.recordReady => '准备录音',
                        _Phase.recording => '● 录音中 $_recSeconds s',
                        _Phase.replay => '录音回放',
                        _Phase.replayDone => '对照答案',
                        _Phase.awaitNext => '待确认',
                        _Phase.done => '完成',
                      }),
                      const Spacer(),
                      Text(
                        _statusText,
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: cs.outline),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _phase == _Phase.idle
                      ? _idleView(context)
                      : _stepView(context),
                ),
              ],
            ),
    );
  }

  Widget _idleView(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic_none_rounded, size: 72, color: cs.primary),
          const SizedBox(height: 16),
          Text(
            '共 ${_steps.length} 个流程步骤',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            '题目内容全程展示 · 录音由你控制 · 回放后对照答案',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: cs.outline),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('开始模拟'),
          ),
        ],
      ),
    );
  }

  /// 步骤进行中的视图：题目常驻（图 + 文）+ 交互区 + 历史记录
  Widget _stepView(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_displayTitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      _displayTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                if (_examImage.isNotEmpty)
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.86,
                          maxHeight: 320,
                        ),
                        child: Image.file(
                          File(_examImage),
                          fit: BoxFit.scaleDown,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                    ),
                  ),
                if (_examImage.isNotEmpty) const SizedBox(height: 12),
                if (_videoFile != null) ...[
                  VideoCard(source: _videoFile!, title: '考试视频', autoPlay: true),
                  const SizedBox(height: 12),
                ],
                if (_displayBody.isNotEmpty)
                  SectionCard(
                    title: '题目内容',
                    icon: Icons.campaign_rounded,
                    children: [
                      EtsTextView(
                        _displayBody,
                        selectable: true,
                        style: const TextStyle(height: 1.7, fontSize: 15),
                      ),
                    ],
                  ),
                if (_showAnswerCard && _referenceAnswer.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SectionCard(
                    title: '参考答案（对照复盘）',
                    icon: Icons.fact_check_rounded,
                    children: [
                      EtsTextView(
                        _referenceAnswer,
                        selectable: true,
                        style: const TextStyle(height: 1.7, fontSize: 14),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                _actionPanel(context),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        _historyStrip(context),
      ],
    );
  }

  /// 阶段交互区：录音前点击开始 / 录音中提前结束 / 回放后下一步
  Widget _actionPanel(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (_phase) {
      case _Phase.recordReady:
        return Center(
          child: Column(
            children: [
              const SizedBox(height: 4),
              FilledButton.icon(
                onPressed: _confirmNext,
                icon: const Icon(Icons.mic_rounded),
                label: const Text('开始录音', style: TextStyle(fontSize: 15)),
                style: FilledButton.styleFrom(minimumSize: const Size(200, 48)),
              ),
              const SizedBox(height: 4),
              Text(
                '准备好就开口，到时自动停止',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: cs.outline),
              ),
            ],
          ),
        );
      case _Phase.recording:
        return Center(
          child: Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle_rounded, size: 12, color: cs.error),
                  const SizedBox(width: 6),
                  Text(
                    '录音中 $_recSeconds s',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(color: cs.error),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _confirmNext, // 提前结束本轮录音
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: const Text('说完了'),
              ),
            ],
          ),
        );
      case _Phase.replayDone:
        return Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  final rec = _lastRecording;
                  if (rec != null && File(rec).existsSync()) {
                    AudioPlayerService.I.open(rec);
                  }
                },
                icon: const Icon(Icons.replay_rounded),
                label: const Text('重听录音'),
              ),
              const SizedBox(width: 8),
              // 我的录音：保存 / 分享 / 复制路径
              OutlinedButton.icon(
                onPressed: () {
                  final rec = _lastRecording;
                  if (rec != null && File(rec).existsSync()) {
                    MediaShare.showSheet(
                      context,
                      rec,
                      title: '我的录音',
                      targetName: '${e.title}-模拟考场录音-${p.basename(rec)}',
                    );
                  }
                },
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('保存 / 分享'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _confirmNext,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('下一步'),
              ),
            ],
          ),
        );
      case _Phase.awaitNext:
        return Center(
          child: FilledButton.icon(
            onPressed: _confirmNext,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('下一步'),
            style: FilledButton.styleFrom(minimumSize: const Size(180, 48)),
          ),
        );
      case _Phase.waiting:
        return Center(
          child: Column(
            children: [
              Text(
                '$_countdown',
                style: Theme.of(context).textTheme.displayMedium
                    ?.copyWith(color: cs.primary, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: _confirmNext, // 提前结束准备
                icon: const Icon(Icons.check_rounded),
                label: const Text('准备好了'),
              ),
            ],
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  /// 步骤历史（可横向滚动，紧凑）
  Widget _historyStrip(BuildContext context) {
    if (_history.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 96,
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.builder(
        itemCount: _history.length,
        itemBuilder: (context, i) {
          final s = _history[i];
          final active = i == _idx;
          return ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: Icon(
              switch (s.type) {
                'view.html' => Icons.text_fields_rounded,
                'file.audio' => Icons.volume_up_rounded,
                'wait' => Icons.timer_outlined,
                'action.record' => Icons.mic_rounded,
                'user.audio' => Icons.hearing_rounded,
                'vari.item' => Icons.subdirectory_arrow_right_rounded,
                _ => Icons.circle_outlined,
              },
              size: 16,
              color: active ? cs.primary : cs.outline,
            ),
            title: Text(
              '${i + 1}. ${s.hint.isNotEmpty ? s.hint : s.type}'
              '${s.filename.isNotEmpty ? ' ${s.filename}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: active ? cs.primary : null,
                fontWeight: active ? FontWeight.w600 : null,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _phaseChip(BuildContext context, String label) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer),
      ),
    );
  }
}
