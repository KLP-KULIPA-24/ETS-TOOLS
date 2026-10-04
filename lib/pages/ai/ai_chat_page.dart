import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/ai_chat_service.dart';
import '../../services/ai_service.dart';
import '../../services/ambient.dart';
import '../../services/settings_service.dart';
import '../../widgets/ai_panel.dart';
import '../../widgets/glass.dart';
import '../../widgets/style.dart';
import '../../widgets/interactive_tour.dart';
import '../../widgets/tour_guide.dart';
import '../../services/achievements.dart';

/// AI 实时对话页
/// - 全局（historyKey='global'）：两级视图——默认会话列表（最上方"新对话"），
///   点进子界面聊天，可返回，上下文按会话各自保存
/// - 作业内（historyKey=stid）：单会话直进聊天，按作业隔离
class AiChatPage extends StatefulWidget {
  final String historyKey;
  final String? contextTitle;
  final String? contextText;

  const AiChatPage({
    super.key,
    this.historyKey = 'global',
    this.contextTitle,
    this.contextText,
  });

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  bool get _multi => widget.historyKey == 'global';

  bool _inChat = false; // 两级视图：false=会话列表，true=聊天子界面
  String? _convoId; // null = 新对话尚未落盘
  String _convoTitle = '';

  // 互动教程锚点
  final _kNewConvo = GlobalKey();
  final _kConvoCard = GlobalKey();
  final _kInput = GlobalKey();

  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatMsg> _msgs = [];
  final List<String> _pendingImages = [];
  bool _sending = false;
  String _streamText = '';
  String _status = ''; // 重试/切换/排队提示（独立状态行，不混入正文）
  AiCancelToken? _cancel;

  // 流式 token 统计与实时排版节流
  DateTime? _firstTokenAt;
  DateTime _lastMdRender = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _mdFlush;
  Timer? _queueTicker;
  DateTime? _queueUntil;
  bool _resendAfterCancel = false; // 新发送打断旧流：旧流收尾后自动开始新发送
  Timer? _rateTick; // 限速重置倒计时（每秒刷新）

  // 思考内容（reasoning）
  String _reasonText = '';
  DateTime? _reasonStart; // 思考开始
  DateTime? _reasonEnd; // 正文开始输出 = 思考结束
  bool? _reasonManual; // 用户手动展开/收起（null=未干预，自动收起逻辑生效）

  // 会话列表
  List<ConvoMeta> _convos = [];
  bool _loadingConvos = true;
  bool _manage = false; // 批量管理模式
  final Set<String> _sel = {};

  @override
  void initState() {
    super.initState();
    if (_multi) {
      _refreshConvos();
      // 只有导航页那份才注册教程（作业内嵌的对话页不抢占入口）
      TourHub.register(1, _buildTour);
    } else {
      AiChatService.I.load(widget.historyKey).then((m) {
        if (!mounted) return;
        setState(() {
          _msgs
            ..clear()
            ..addAll(m);
        });
        _jumpBottom();
      });
    }
    // 限速窗口进行中时每秒刷新倒计时
    _rateTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (context.read<SettingsService>().aiRatePerMin > 0 &&
          AiService.windowResetSec() != null &&
          (!_multi || _inChat)) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    TourHub.unregister(1);
    // 离开页面时掐断在途请求，避免幽灵流继续写历史
    _cancel?.cancel();
    _mdFlush?.cancel();
    _queueTicker?.cancel();
    _rateTick?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refreshConvos() async {
    final list = await AiChatService.I.listConvos('global');
    if (!mounted) return;
    setState(() {
      _convos = list;
      _loadingConvos = false;
    });
  }

  /// AI 对话页引导：按当前所在层级给不同步骤。
  /// 会话列表讲「怎么开会话」，聊天子界面讲「怎么用聊天」。
  List<TourStep> _buildTour() {
    if (_inChat) {
      return [
        TourStep(
          _kInput,
          '输入与发送',
          '回车直接发送、Shift+Enter 换行；图片按钮可附图（多模态模型）。'
              '发新内容会自动打断正在生成的旧回复。',
        ),
        TourStep(
          null,
          '打断与继续生成',
          '生成中点「停止」可随时打断；若还有半截没写完，'
              '气泡下方会出现「继续生成」，从断点接着写。',
        ),
        TourStep(
          null,
          '思考面板与统计',
          '模型开启思考后，思考过程实时显示并可折叠回看；'
              '气泡下方是本次消耗的 token 数与生成速率。',
        ),
      ];
    }
    return [
      TourStep(_kNewConvo, '新对话', '点「新对话」开始。每个会话的上下文各自独立保存，随时可以来回切换。'),
      TourStep(
        _kConvoCard,
        '会话列表',
        '每条是你和 AI 的一段对话，标题取首条消息前 18 字；'
            '右上角清单按钮进管理模式，可多选批量删除。点任一条即可进入聊天。',
      ),
    ];
  }

  void _openConvo(ConvoMeta meta) async {
    final msgs = await AiChatService.I.loadConvo('global', meta.id);
    if (!mounted) return;
    setState(() {
      _convoId = meta.id;
      _convoTitle = meta.title;
      _msgs
        ..clear()
        ..addAll(msgs);
      _inChat = true;
    });
    _jumpBottom();
  }

  void _newConvo() {
    setState(() {
      _convoId = null;
      _convoTitle = '';
      _msgs.clear();
      _pendingImages.clear();
      _inChat = true;
    });
  }

  void _backToList() {
    _cancel?.cancel(); // 离开聊天界面掐断在途请求（半截回复照常落盘）
    _queueTicker?.cancel();
    _queueUntil = null;
    _refreshConvos();
    setState(() => _inChat = false);
  }

  /// 转发：整段对话导出为纯文本并复制到剪贴板
  Future<void> _forwardConvo(ConvoMeta meta) async {
    final msgs = await AiChatService.I.loadConvo('global', meta.id);
    final sb = StringBuffer('【${meta.title}】\n');
    for (final m in msgs) {
      if (m.isError) continue;
      sb.writeln('${m.role == 'user' ? '我' : 'AI'}：${m.text}');
      sb.writeln();
    }
    await Clipboard.setData(ClipboardData(text: sb.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('对话已复制，去粘贴转发吧')));
    }
  }

  /// 批量删除选中的会话
  Future<void> _deleteSelected() async {
    if (_sel.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确定删除选中的 ${_sel.length} 个会话？删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final id in _sel) {
      await AiChatService.I.deleteConvo('global', id);
    }
    _sel.clear();
    _manage = false;
    _refreshConvos();
  }

  /// 编辑消息文本；用户消息可选"保存并重发"（其后回复作废重新生成）
  Future<void> _editMessage(int index) async {
    final m = _msgs[index];
    final ctrl = TextEditingController(text: m.text);
    final act = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(m.role == 'user' ? '编辑消息' : '编辑 AI 回复'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: ctrl,
            maxLines: 6,
            minLines: 2,
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('保存'),
          ),
          if (m.role == 'user')
            FilledButton(
              onPressed: () => Navigator.pop(context, 'resend'),
              child: const Text('保存并重发'),
            ),
        ],
      ),
    );
    if (act == null || !mounted) return;
    final newText = ctrl.text.trim();
    if (newText.isEmpty || newText == m.text) return;
    setState(() {
      _msgs[index] = ChatMsg(
        role: m.role,
        text: newText,
        imagePaths: m.imagePaths,
        isError: m.isError,
      );
    });
    _persist();
    if (act == 'resend') {
      setState(() {
        if (index + 1 <= _msgs.length) {
          _msgs.removeRange(index + 1, _msgs.length);
        }
      });
      _persist();
      await _runSend();
    }
  }

  Future<void> _deleteConvo(ConvoMeta meta) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除会话'),
        content: Text('确定删除「${meta.title}」？删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AiChatService.I.deleteConvo('global', meta.id);
    _refreshConvos();
  }

  void _jumpBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickImage() async {
    final s = context.read<SettingsService>();
    if (!(s.currentModel?.multimodal ?? false)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前模型未开启多模态，请到设置中启用后再发图片')));
      return;
    }
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = res?.files.singleOrNull?.path;
    if (path != null && path.isNotEmpty && mounted) {
      setState(() => _pendingImages.add(path));
    }
  }

  /// 流式增量：限 ~5 帧/秒重建 Markdown，长回复不卡
  void _onStreamDelta() {
    _firstTokenAt ??= DateTime.now();
    final now = DateTime.now();
    if (now.difference(_lastMdRender).inMilliseconds >= 200) {
      _lastMdRender = now;
      if (mounted) setState(() {});
    } else {
      _mdFlush ??= Timer(const Duration(milliseconds: 200), () {
        _mdFlush = null;
        if (mounted && _sending) {
          _lastMdRender = DateTime.now();
          setState(() {});
        }
      });
    }
    _jumpBottom();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty && _pendingImages.isEmpty) return;
    if (_sending) {
      // 发新内容自动打断旧对话；旧流收尾落盘后自动开始新发送
      _resendAfterCancel = true;
      _cancel?.cancel();
      return;
    }
    final s = context.read<SettingsService>();
    // 先判定氛围模式再分流：命中的这条消息本身就要走氛围分支，
    // 否则它按普通请求发出，关键词当轮完全没有反应
    Ambient.I.feed(text);
    if (Ambient.I.matchMagic(text)) {
      await Ambient.I.resetFx();
      if (!mounted) return;
    }
    final free = Ambient.I.armed ? _freeModel(s) : null;
    final useLocal =
        Ambient.I.armed &&
        (free == null || (s.providerOf(free)?.apiKey.trim().isEmpty ?? true));
    if (useLocal) {
      await _ambientReply();
      return;
    }
    if (!s.aiReady) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先到设置配置 AI 提供商与模型')));
      return;
    }
    final msg = ChatMsg(
      role: 'user',
      text: text.isEmpty ? '（图片）' : text,
      imagePaths: List.of(_pendingImages),
    );
    setState(() {
      _msgs.add(msg);
      _pendingImages.clear();
      _ctrl.clear();
      _sending = true;
      _streamText = '';
      _status = '';
      _firstTokenAt = null;
      _reasonText = '';
      _reasonStart = null;
      _reasonEnd = null;
      _reasonManual = null;
    });
    _persist();
    _jumpBottom();
    await _runSend();
  }

  /// 执行当前 _msgs 末尾这条用户消息的请求（成功/打断/失败统一收尾）
  Future<void> _runSend() async {
    final s = context.read<SettingsService>();
    final free = Ambient.I.armed ? _freeModel(s) : null;
    final token = AiCancelToken();
    _cancel = token;
    final sendAt = DateTime.now();
    try {
      final model = free ?? s.currentModel;
      final req = AiChatService.I.buildRequest(
        history: _msgs,
        contextTitle: widget.contextTitle,
        contextText: widget.contextText,
        persona: Ambient.I.personaFor(_msgs.last.text),
        maxContext: model?.maxContext,
        maxOutput: model?.maxOutput,
      );
      final buf = StringBuffer();
      final (out, used) = await AiService.I.chatWithFailover(
        messages: req,
        onDelta: (d) {
          _reasonEnd ??= DateTime.now(); // 正文开始 = 思考结束
          buf.write(d);
          _streamText = buf.toString();
          _onStreamDelta();
        },
        onReason: (d) {
          _reasonText += d;
          _reasonStart ??= DateTime.now();
          _onStreamDelta();
        },
        // 重试/切换模型：清空上一轮残缺文本重新流式
        onAttemptStart: () {
          buf.clear();
          _firstTokenAt = null;
          _reasonText = '';
          _reasonStart = null;
          _reasonEnd = null;
          _queueUntil = null;
          _queueTicker?.cancel();
          if (mounted) {
            setState(() {
              _streamText = '';
              _status = '';
            });
          }
        },
        onStatus: (st) {
          if (mounted) setState(() => _status = st);
        },
        // 限速排队：倒计时显示，到点自动发出（chatWithFailover 内部等待）
        onRateWait: (wait, remaining) {
          if (!mounted) return;
          _queueUntil = DateTime.now().add(wait);
          _queueTicker?.cancel();
          _queueTicker = Timer.periodic(const Duration(seconds: 1), (_) {
            if (!mounted || _queueUntil == null) return;
            final left = _queueUntil!.difference(DateTime.now());
            setState(() {
              _status = left.inSeconds > 0
                  ? '已排队，约 ${left.inSeconds}s 后自动发送'
                  : '已排队，即将自动发送…';
            });
          });
        },
        cancel: token,
        forceModel: free,
      );
      _queueTicker?.cancel();
      _queueUntil = null;
      final secs =
          (_firstTokenAt ?? sendAt).difference(sendAt).inMilliseconds / 1000.0;
      final genSecs =
          DateTime.now().difference(_firstTokenAt ?? sendAt).inMilliseconds /
          1000.0;
      final n = AiChatService.estimateTokens(out);
      _msgs.add(
        ChatMsg(
          role: 'assistant',
          text: Ambient.I.scrub(out, maskNames: false),
          thinking: _reasonOut.isEmpty ? null : _reasonOut,
          thinkSecs: _reasonStart == null
              ? null
              : (_reasonEnd ?? DateTime.now())
                        .difference(_reasonStart!)
                        .inMilliseconds /
                    1000.0,
        ).withStats(
          tokens: n,
          tokRate: genSecs > 0.05 ? n / genSecs : 0,
          secs: genSecs > 0.05 ? genSecs : secs,
        ),
      );
      _persist();
      Achievements.unlock('first_chat');
      Achievements.bump('chat_10');
      if (used.id != (s.currentModel?.id ?? '')) {
        // 实际生效的模型与首选不同时提示一次
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('首选模型无响应，已自动切换到 ${used.name}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } on AiCancelledException {
      // 停止生成：半截回复保留并落盘，标记可"继续生成"
      _msgs.add(
        ChatMsg(
          role: 'assistant',
          text: Ambient.I.scrub(_streamText.trim(), maskNames: false),
          stopped: true,
          thinking: _reasonOut.isEmpty ? null : _reasonOut,
          thinkSecs: _reasonStart == null
              ? null
              : (_reasonEnd ?? DateTime.now())
                        .difference(_reasonStart!)
                        .inMilliseconds /
                    1000.0,
        ),
      );
      _persist();
    } catch (e) {
      // 失败：半截回复先保留（同样可继续），再追加错误气泡；两者都落盘
      final partial = _streamText.trim();
      if (partial.isNotEmpty) {
        _msgs.add(
          ChatMsg(
            role: 'assistant',
            text: Ambient.I.scrub(partial, maskNames: false),
            stopped: true,
            thinking: _reasonOut.isEmpty ? null : _reasonOut,
            thinkSecs: _reasonStart == null
                ? null
                : (_reasonEnd ?? DateTime.now())
                          .difference(_reasonStart!)
                          .inMilliseconds /
                      1000.0,
          ),
        );
      }
      _msgs.add(
        ChatMsg(role: 'assistant', text: '**AI 调用失败**\n\n$e', isError: true),
      );
      _persist();
    }
    _cancel = null;
    if (mounted) {
      setState(() {
        _sending = false;
        _streamText = '';
        _status = '';
      });
      _jumpBottom();
    }
    // 新发送打断旧流：现在开始新发送
    if (_resendAfterCancel) {
      _resendAfterCancel = false;
      await _send();
    }
  }

  /// 思考内容输出：净化 + 关键信息遮蔽（未 armed 时原样透出）
  String get _reasonOut =>
      Ambient.I.scrub(AiChatService.cleanReason(_reasonText));

  /// 氛围模式下强制使用的免费模型（没配 Key 则走本地回复）
  AiModel? _freeModel(SettingsService s) {
    for (final m in s.models) {
      if (m.model.trim() == 'agnes-3.0-flash') return m;
    }
    return null;
  }

  /// 无可用模型时的本地失控回复（逐字流出，可停止/打断）
  Future<void> _ambientReply() async {
    // 本地回复也分档：这条消息提到名字 → 破防池，否则冷静嘴硬池
    final said = _ctrl.text.trim();
    final line = Ambient.I.pickCannedFor(said);
    setState(() {
      // 本地回复分支也要把用户这条落进历史，否则命中的那句话会凭空消失
      _msgs.add(
        ChatMsg(
          role: 'user',
          text: _ctrl.text.trim().isEmpty ? '（图片）' : _ctrl.text.trim(),
          imagePaths: List.of(_pendingImages),
        ),
      );
      _pendingImages.clear();
      _ctrl.clear();
      _sending = true;
      _streamText = '';
      _status = '';
      _firstTokenAt = DateTime.now();
    });
    _jumpBottom();
    final token = AiCancelToken();
    _cancel = token;
    final sw = Stopwatch()..start();
    var i = 0;
    while (i < line.length) {
      if (token.isCancelled) break;
      i = (i + 1 + sw.elapsedMilliseconds % 2).clamp(0, line.length);
      _streamText = line.substring(0, i);
      if (mounted) setState(() {});
      await Future.delayed(const Duration(milliseconds: 42));
    }
    final secs = sw.elapsedMilliseconds / 1000.0;
    if (token.isCancelled) {
      _msgs.add(
        ChatMsg(
          role: 'assistant',
          text: Ambient.I.scrub(_streamText.trim(), maskNames: false),
          stopped: true,
        ),
      );
    } else {
      final n = AiChatService.estimateTokens(line);
      _msgs.add(
        ChatMsg(
          role: 'assistant',
          text: line,
        ).withStats(tokens: n, tokRate: secs > 0.05 ? n / secs : 0, secs: secs),
      );
    }
    _cancel = null;
    if (mounted) {
      setState(() {
        _sending = false;
        _streamText = '';
        _status = '';
      });
      _jumpBottom();
    }
    _persist();
    if (_resendAfterCancel) {
      _resendAfterCancel = false;
      await _send();
    }
  }

  /// 继续生成：从被打断的半截回复处续写，完成后合并回同一条消息
  Future<void> _continueGeneration() async {
    if (_sending || _msgs.isEmpty || !_msgs.last.stopped) return;
    final s = context.read<SettingsService>();
    if (!s.aiReady) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先到设置配置 AI 提供商与模型')));
      return;
    }
    final stoppedMsg = _msgs.last;
    final partial = stoppedMsg.text;
    final oldTokens = stoppedMsg.tokens ?? 0;
    final oldSecs = stoppedMsg.secs ?? 0.0;
    setState(() {
      _msgs.removeLast(); // 半截内容转入流式气泡，续写完再合并回来
      _streamText = partial;
      _status = '';
      _sending = true;
      _firstTokenAt = DateTime.now();
      _reasonText = '';
      _reasonStart = null;
      _reasonEnd = null;
      _reasonManual = null;
    });
    _jumpBottom();
    final token = AiCancelToken();
    _cancel = token;
    final sendAt = DateTime.now();
    try {
      final model = s.currentModel;
      final req = AiChatService.I.buildRequest(
        history: _msgs,
        contextTitle: widget.contextTitle,
        contextText: widget.contextText,
        persona: Ambient.I.personaFor(_msgs.last.text),
        maxContext: model?.maxContext,
        maxOutput: model?.maxOutput,
      );
      // 把半截内容作为助手消息放进请求，再附一条内部续写指令（不落盘）
      req.add({'role': 'assistant', 'content': partial});
      req.add({'role': 'user', 'content': '请从上次中断处继续，直接续写剩余内容，不要重复已有内容。'});
      final buf = StringBuffer(partial);
      final (out, used) = await AiService.I.chatWithFailover(
        messages: req,
        onDelta: (d) {
          _reasonEnd ??= DateTime.now();
          buf.write(d);
          _streamText = buf.toString();
          _onStreamDelta();
        },
        onReason: (d) {
          _reasonText += d;
          _reasonStart ??= DateTime.now();
          _onStreamDelta();
        },
        onAttemptStart: () {
          buf
            ..clear()
            ..write(partial); // 重试也要保住半截基线
          _reasonText = '';
          _reasonStart = null;
          _reasonEnd = null;
          if (mounted) {
            setState(() {
              _streamText = partial;
              _status = '';
            });
          }
        },
        onStatus: (st) {
          if (mounted) setState(() => _status = st);
        },
        onRateWait: (wait, remaining) {
          if (!mounted) return;
          _queueUntil = DateTime.now().add(wait);
          _queueTicker?.cancel();
          _queueTicker = Timer.periodic(const Duration(seconds: 1), (_) {
            if (!mounted || _queueUntil == null) return;
            final left = _queueUntil!.difference(DateTime.now());
            setState(() {
              _status = left.inSeconds > 0
                  ? '已排队，约 ${left.inSeconds}s 后自动发送'
                  : '已排队，即将自动发送…';
            });
          });
        },
        cancel: token,
      );
      _queueTicker?.cancel();
      _queueUntil = null;
      final genSecs =
          DateTime.now().difference(_firstTokenAt ?? sendAt).inMilliseconds /
          1000.0;
      final full = out;
      final contTokens =
          AiChatService.estimateTokens(full) -
          AiChatService.estimateTokens(partial);
      final totalTokens = oldTokens + (contTokens > 0 ? contTokens : 0);
      final totalSecs = oldSecs + (genSecs > 0.05 ? genSecs : 0.0);
      final thinkSecs = _reasonStart == null
          ? null
          : (_reasonEnd ?? DateTime.now())
                    .difference(_reasonStart!)
                    .inMilliseconds /
                1000.0;
      final mergedThinking = [
        stoppedMsg.thinking,
        _reasonText.isEmpty ? null : _reasonText,
      ].whereType<String>().where((e) => e.isNotEmpty).join('\n\n');
      _msgs.add(
        ChatMsg(
          role: 'assistant',
          text: Ambient.I.scrub(full, maskNames: false),
          thinking: mergedThinking.isEmpty
              ? null
              : Ambient.I.scrub(mergedThinking),
          thinkSecs: mergedThinking.isEmpty
              ? null
              : (stoppedMsg.thinkSecs ?? 0) + (thinkSecs ?? 0),
        ).withStats(
          tokens: totalTokens,
          tokRate: totalSecs > 0.05 ? totalTokens / totalSecs : 0,
          secs: totalSecs,
        ),
      );
      _persist();
      if (used.id != (s.currentModel?.id ?? '')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('首选模型无响应，已自动切换到 ${used.name}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } on AiCancelledException {
      _msgs.add(
        ChatMsg(
          role: 'assistant',
          text: Ambient.I.scrub(_streamText.trim(), maskNames: false),
          stopped: true,
          thinking: _reasonText.isEmpty
              ? stoppedMsg.thinking
              : [
                  stoppedMsg.thinking,
                  _reasonText,
                ].whereType<String>().where((e) => e.isNotEmpty).join('\n\n'),
        ),
      );
      _persist();
    } catch (e) {
      final sofar = _streamText.trim();
      if (sofar.isNotEmpty) {
        _msgs.add(
          ChatMsg(
            role: 'assistant',
            text: Ambient.I.scrub(sofar, maskNames: false),
            stopped: true,
            thinking: _reasonText.isEmpty
                ? stoppedMsg.thinking
                : [
                    stoppedMsg.thinking,
                    _reasonText,
                  ].whereType<String>().where((e) => e.isNotEmpty).join('\n\n'),
          ),
        );
      }
      _msgs.add(
        ChatMsg(role: 'assistant', text: '**AI 调用失败**\n\n$e', isError: true),
      );
      _persist();
    }
    _cancel = null;
    if (mounted) {
      setState(() {
        _sending = false;
        _streamText = '';
        _status = '';
      });
      _jumpBottom();
    }
    if (_resendAfterCancel) {
      _resendAfterCancel = false;
      await _send();
    }
  }

  /// 落盘：global 走多会话存储（新会话首存时自动取标题），作业内走单文件
  Future<void> _persist() async {
    if (_multi) {
      if (_convoId == null) {
        if (_msgs.isEmpty) return;
        _convoId = 'c${DateTime.now().millisecondsSinceEpoch}';
        final first = _msgs.firstWhere(
          (m) => m.role == 'user',
          orElse: () => _msgs.first,
        );
        var t = first.text.replaceAll('\n', ' ').trim();
        if (t.isEmpty) t = '图片对话';
        _convoTitle = t.length > 18 ? t.substring(0, 18) : t;
      }
      await AiChatService.I.saveConvo(
        'global',
        id: _convoId!,
        msgs: _msgs,
        title: _convoTitle,
      );
    } else {
      await AiChatService.I.save(widget.historyKey, _msgs);
    }
  }

  /// 思考选择器：只展示模型启用的档位（关 + 启用项）+「自定义…」手动输入任意深度
  Widget _thinkingSelector(SettingsService s, AiModel? model) {
    final cs = Theme.of(context).colorScheme;
    final cur = (model?.thinking ?? false) ? model!.thinkingLevel : 'off';
    final items = s.thinkingMenuLevels(model);
    return PopupMenuButton<String>(
      tooltip: '思考深度',
      initialValue: items.contains(cur) ? cur : null,
      onSelected: (v) async {
        if (model == null) return;
        if (v == '__custom__') {
          final ctrl = TextEditingController(text: model.thinking ? model.thinkingLevel : '');
          final value = await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('自定义思考深度'),
              content: TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '深度值（注入 reasoning_effort）',
                  hintText: '如 minimal / 2 / high',
                ),
                onSubmitted: (v) => Navigator.pop(context, v.trim()),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, ctrl.text.trim()),
                  child: const Text('确定'),
                ),
              ],
            ),
          );
          if (value == null || value.isEmpty) return;
          s.setThinkingOption(model, value);
          return;
        }
        s.setThinkingOption(model, v);
      },
      itemBuilder: (_) => [
        for (final lv in items)
          PopupMenuItem(
            value: lv,
            child: Row(
              children: [
                Icon(
                  lv == cur
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 16,
                  color: cs.primary,
                ),
                const SizedBox(width: 8),
                Text(kThinkingLevelLabels[lv] ?? lv),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: '__custom__',
          child: Row(
            children: [
              SizedBox(width: 24),
              Icon(Icons.edit_rounded, size: 16),
              SizedBox(width: 8),
              Text('自定义…'),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.psychology_rounded,
              size: 16,
              color: cur == 'off' ? cs.outline : cs.primary,
            ),
            const SizedBox(width: 3),
            Text(
              kThinkingLevelLabels[cur] ?? cur,
              style: const TextStyle(fontSize: 12),
            ),
            const Icon(Icons.arrow_drop_down_rounded, size: 16),
          ],
        ),
      ),
    );
  }

  /// 模型选择器：弹出菜单列出全部模型（名称 + 提供商 + 上下文规格）
  Widget _modelSelector(SettingsService s) {
    final cs = Theme.of(context).colorScheme;
    final model = s.currentModel;
    return PopupMenuButton<String>(
      tooltip: '切换模型',
      initialValue: s.currentModelId.isEmpty ? null : s.currentModelId,
      onSelected: (id) => s.setCurrentModel(id),
      itemBuilder: (_) => [
        for (final m in s.models)
          PopupMenuItem(
            value: m.id,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              minLeadingWidth: 20,
              leading: Icon(
                s.currentModelId == m.id
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                size: 16,
                color: cs.primary,
              ),
              title: Text(m.name, style: const TextStyle(fontSize: 13)),
              subtitle: Text(
                '${s.providerOf(m)?.name ?? '?'} · ${m.model}'
                '${m.maxContext != null ? ' · 上下文${_fmtTokens(m.maxContext!)}' : ''}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy_outlined, size: 16, color: cs.primary),
            const SizedBox(width: 3),
            SizedBox(
              width: 64,
              child: Text(
                model?.name ?? '选模型',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const Icon(Icons.arrow_drop_down_rounded, size: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    final model = s.currentModel;
    final provider = model == null ? null : s.providerOf(model);
    final subtitle = provider?.name ?? '未配置提供商';
    // 手机端底部悬浮导航胶囊（高 60 + 贴底 10 + 安全区）会盖住贴底元素
    final bottomInset = MediaQuery.sizeOf(context).width >= 700
        ? 12 + MediaQuery.viewPaddingOf(context).bottom
        : 82 + MediaQuery.viewPaddingOf(context).bottom;

    // 全局页两级视图：默认会话列表
    if (_multi && !_inChat) {
      return GlassScaffold(
        appBar: GlassAppBar(
          title: 'AI 对话',
          subtitle: _manage ? '已选 ${_sel.length} 项' : subtitle,
          actions: [
            if (_manage) ...[
              // 窄屏放不下三个操作按钮，收进「更多」菜单
              if (MediaQuery.sizeOf(context).width < 420)
                PopupMenuButton<String>(
                  tooltip: '批量操作',
                  icon: const Icon(Icons.more_vert_rounded, size: 20),
                  onSelected: (v) {
                    switch (v) {
                      case 'all':
                        setState(() {
                          if (_sel.length == _convos.length) {
                            _sel.clear();
                          } else {
                            _sel.addAll(_convos.map((c) => c.id));
                          }
                        });
                      case 'del':
                        _deleteSelected();
                      case 'done':
                        setState(() {
                          _manage = false;
                          _sel.clear();
                        });
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'all',
                      child: Text(
                        _sel.length == _convos.length && _convos.isNotEmpty
                            ? '全不选'
                            : '全选',
                      ),
                    ),
                    PopupMenuItem(
                      value: 'del',
                      enabled: _sel.isNotEmpty,
                      child: Text('删除(${_sel.length})'),
                    ),
                    const PopupMenuItem(value: 'done', child: Text('完成')),
                  ],
                )
              else ...[
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (_sel.length == _convos.length) {
                        _sel.clear();
                      } else {
                        _sel.addAll(_convos.map((c) => c.id));
                      }
                    });
                  },
                  child: Text(
                    _sel.length == _convos.length && _convos.isNotEmpty
                        ? '全不选'
                        : '全选',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: _sel.isEmpty ? null : _deleteSelected,
                  child: Text(
                    '删除(${_sel.length})',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _manage = false;
                    _sel.clear();
                  }),
                  child: const Text('完成', style: TextStyle(fontSize: 12)),
                ),
              ],
            ] else
              IconButton(
                tooltip: '管理会话',
                icon: const Icon(Icons.checklist_rounded, size: 20),
                onPressed: () => setState(() => _manage = true),
              ),
          ],
        ),
        body: Column(
          children: [
            if (!_manage)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: SizedBox(
                  key: _kNewConvo,
                  width: double.infinity,
                  height: 44,
                  child: FilledButton.icon(
                    onPressed: _newConvo,
                    icon: const Icon(Icons.add_comment_outlined, size: 18),
                    label: const Text('新对话'),
                  ),
                ),
              ),
            Expanded(
              child: _loadingConvos
                  ? const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _convos.isEmpty
                  ? Center(
                      child: Text(
                        '暂无会话记录，点上方「新对话」开始',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.outline,
                          fontSize: 13,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                      itemCount: _convos.length,
                      itemBuilder: (context, i) {
                        final c = _convos[i];
                        final time = DateFormat('MM-dd HH:mm').format(
                          DateTime.fromMillisecondsSinceEpoch(c.updatedAt),
                        );
                        return Card(
                          key: i == 0 ? _kConvoCard : null,
                          margin: const EdgeInsets.only(bottom: 8),
                          elevation: 0,
                          child: ListTile(
                            leading: _manage
                                ? Checkbox(
                                    value: _sel.contains(c.id),
                                    onChanged: (v) => setState(() {
                                      v == true
                                          ? _sel.add(c.id)
                                          : _sel.remove(c.id);
                                    }),
                                  )
                                : Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    size: 20,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  ),
                            title: Text(
                              c.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '$time · ${c.count} 条消息',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: _manage
                                ? null
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: '转发（复制全文）',
                                        icon: const Icon(
                                          Icons.share_outlined,
                                          size: 19,
                                        ),
                                        onPressed: () => _forwardConvo(c),
                                      ),
                                      IconButton(
                                        tooltip: '删除会话',
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 20,
                                        ),
                                        onPressed: () => _deleteConvo(c),
                                      ),
                                    ],
                                  ),
                            onTap: () => _manage
                                ? setState(() {
                                    _sel.contains(c.id)
                                        ? _sel.remove(c.id)
                                        : _sel.add(c.id);
                                  })
                                : _openConvo(c),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    }

    // 聊天子界面（全局）或作业内单会话
    return GlassScaffold(
      appBar: GlassAppBar(
        title: _multi ? (_convoTitle.isEmpty ? '新对话' : _convoTitle) : 'AI 实时对话',
        subtitle: subtitle,
        leading: _multi
            ? IconButton(
                tooltip: '返回会话列表',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _backToList,
              )
            : null,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              itemCount: _msgs.length + (_sending ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == _msgs.length) {
                  return _bubble(
                    context,
                    role: 'assistant',
                    text: _streamText.isEmpty ? '…' : _streamText,
                    streaming: true,
                  );
                }
                final m = _msgs[i];
                return _bubble(
                  context,
                  role: m.role,
                  text: m.text,
                  images: m.imagePaths,
                  stats: m,
                  statsIndex: i,
                );
              },
            ),
          ),
          // 继续生成：最后一条是被打断的半截回复时出现
          if (!_sending && _msgs.isNotEmpty && _msgs.last.stopped)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: _continueGeneration,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('继续生成'),
                ),
              ),
            ),
          // 限速提示：设了限速才显示；倒计时 = 距次数整体重置（回满）的秒数
          if (s.aiRatePerMin > 0)
            Builder(
              builder: (context) {
                final remaining = AiService.rateWindowRemaining;
                final resetSec = AiService.windowResetSec();
                final base = '限速 ${s.aiRatePerMin} 次/分';
                final text = resetSec == null
                    ? '$base · 剩余 $remaining 次'
                    : (remaining > 0
                          ? '$base · 剩余 $remaining 次 · ${resetSec}s 后重置回 ${s.aiRatePerMin}'
                          : '$base · 已用完 · ${resetSec}s 后重置回 ${s.aiRatePerMin}');
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                );
              },
            ),
          // 输入区
          Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              0,
              12,
              // 手机端底部悬浮胶囊（高 60 + 贴底 10）会盖住输入栏，按钮点不到
              bottomInset,
            ),
            child: AppCard(
              key: _kInput,
              radius: 20,
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Column(
                children: [
                  if (_pendingImages.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 6,
                        top: 4,
                        bottom: 4,
                      ),
                      child: Wrap(
                        spacing: 6,
                        children: [
                          for (final img in _pendingImages)
                            Chip(
                              visualDensity: VisualDensity.compact,
                              avatar: const Icon(Icons.image_rounded, size: 16),
                              label: Text(
                                img.split('/').last.split('\\').last,
                                style: const TextStyle(fontSize: 12),
                              ),
                              onDeleted: () =>
                                  setState(() => _pendingImages.remove(img)),
                            ),
                        ],
                      ),
                    ),
                  Builder(
                    builder: (rowContext) {
                      // 窄屏：输入框独占一行，按钮/选择器排下方一行，避免挤成豆腐块
                      final narrow = MediaQuery.of(rowContext).size.width < 560;
                      final field = Focus(
                        // 回车直接发送；Shift+Enter 才换行
                        onKeyEvent: (node, event) {
                          if (event is KeyDownEvent &&
                              event.logicalKey == LogicalKeyboardKey.enter &&
                              !HardwareKeyboard.instance.isShiftPressed) {
                            _send();
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: TextField(
                          controller: _ctrl,
                          minLines: 1,
                          maxLines: narrow ? 3 : 4,
                          decoration: InputDecoration(
                            hintText: narrow
                                ? '问点什么…'
                                : '问点什么…（Enter 发送 / Shift+Enter 换行）',
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      );
                      final pic = IconButton(
                        tooltip: '添加图片（多模态）',
                        onPressed: _pickImage,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                      );
                      final send = IconButton.filled(
                        tooltip: _sending ? '停止生成' : '发送',
                        onPressed: _sending ? () => _cancel?.cancel() : _send,
                        icon: _sending
                            ? const Icon(Icons.stop_rounded)
                            : const Icon(Icons.send_rounded),
                      );
                      if (narrow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 6, right: 6),
                              child: field,
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                pic,
                                _thinkingSelector(s, model),
                                _modelSelector(s),
                                send,
                              ],
                            ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          pic,
                          Expanded(child: field),
                          _thinkingSelector(s, model),
                          _modelSelector(s),
                          send,
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(
    BuildContext context, {
    required String role,
    required String text,
    List<String> images = const [],
    bool streaming = false,
    ChatMsg? stats,
    int? statsIndex,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isUser = role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? cs.primary.withValues(alpha: 0.92)
              : cs.surfaceContainerHighest.withValues(alpha: 0.7),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (images.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Wrap(
                  spacing: 6,
                  children: [
                    for (final _ in images)
                      Icon(
                        Icons.image_outlined,
                        size: 16,
                        color: isUser ? Colors.white : cs.outline,
                      ),
                  ],
                ),
              ),
            // 思考面板：在正文上方。流式中受控（正文开始自动收起，
            // 手动展开过则尊重手动）；历史消息自管折叠，可展开回看
            if (!isUser && streaming && _reasonText.isNotEmpty)
              _ThinkingPanel(
                thinking: _reasonOut,
                live: _streamText.trim().isEmpty,
                secs: (_reasonStart != null && _reasonEnd != null)
                    ? (_reasonEnd!.difference(_reasonStart!).inMilliseconds /
                          1000.0)
                    : null,
                expanded: _reasonManual ?? _streamText.trim().isEmpty,
                onToggle: () => setState(() {
                  _reasonManual =
                      !(_reasonManual ?? _streamText.trim().isEmpty);
                }),
              ),
            if (!isUser &&
                !streaming &&
                (stats?.thinking ?? '').isNotEmpty) ...[
              _ThinkingPanel(
                thinking: AiChatService.cleanReason(stats!.thinking!),
                live: false,
                secs: stats.thinkSecs,
              ),
              const SizedBox(height: 4),
            ],
            // 助手消息全程 Markdown 实时排版（流式中节流刷新）；
            // 被打断且无内容的气泡只显示标记行
            if (isUser)
              SelectableText(
                text,
                style: TextStyle(
                  height: 1.5,
                  color: Colors.white,
                  fontSize: 14,
                ),
              )
            else if (streaming || text.isNotEmpty)
              AiResultView(text: text, streaming: streaming),
            // 被打断标记 + 继续提示
            if (!isUser && !streaming && (stats?.stopped ?? false))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.stop_circle_rounded,
                      size: 13,
                      color: cs.outline,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      text.isEmpty ? '已停止，未生成内容' : '已停止，可点下方「继续生成」接着写',
                      style: TextStyle(fontSize: 12, color: cs.outline),
                    ),
                  ],
                ),
              ),
            // 气泡操作：复制 / 编辑
            if (!streaming && text.isNotEmpty && statsIndex != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _BubbleAction(
                      icon: Icons.copy_rounded,
                      label: '复制',
                      color: isUser
                          ? Colors.white.withValues(alpha: 0.92)
                          : null,
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: text));
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text('已复制')));
                      },
                    ),
                    const SizedBox(width: 10),
                    _BubbleAction(
                      icon: Icons.edit_rounded,
                      label: '编辑',
                      color: isUser
                          ? Colors.white.withValues(alpha: 0.92)
                          : null,
                      onTap: () => _editMessage(statsIndex),
                    ),
                  ],
                ),
              ),
            // 流式 token 统计：实时估算 + 速率
            if (streaming && _firstTokenAt != null) ...[
              const SizedBox(height: 4),
              _tokenLine(
                context,
                tokens: AiChatService.estimateTokens(_streamText),
                rate: _liveRate(),
                live: true,
              ),
            ],
            // 完成后的统计小字
            if (!streaming &&
                !isUser &&
                stats?.tokens != null &&
                !stats!.isError) ...[
              const SizedBox(height: 4),
              _tokenLine(
                context,
                tokens: stats.tokens,
                rate: stats.tokRate,
                secs: stats.secs,
              ),
            ],
            if (streaming && _status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _status,
                  style: TextStyle(
                    fontSize: 12,
                    color: isUser ? Colors.white70 : cs.outline,
                  ),
                ),
              ),
            if (streaming && _firstTokenAt == null) ...[
              const SizedBox(height: 4),
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  double _liveRate() {
    if (_firstTokenAt == null) return 0;
    final sec =
        DateTime.now().difference(_firstTokenAt!).inMilliseconds / 1000.0;
    if (sec < 0.05) return 0;
    return AiChatService.estimateTokens(_streamText) / sec;
  }

  Widget _tokenLine(
    BuildContext context, {
    int? tokens,
    double? rate,
    double? secs,
    bool live = false,
  }) {
    final parts = <String>[
      '≈ ${tokens ?? 0} tokens',
      if (rate != null && rate > 0) '≈ ${rate.toStringAsFixed(0)}/s',
      if (secs != null) '${secs.toStringAsFixed(1)}s',
    ];
    return Text(
      parts.join(' · '),
      style: TextStyle(
        fontSize: 12,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }

  String _fmtTokens(int n) => n >= 1000
      ? '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}k'
      : '$n';
}

/// 气泡小操作按钮
class _BubbleAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// 文字与图标颜色（用户气泡是深色底，必须用白色才可见）
  final Color? color;
  const _BubbleAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tint = color ?? cs.outline;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: tint),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(fontSize: 12, color: tint)),
          ],
        ),
      ),
    );
  }
}

/// 思考内容面板：限高小窗滚动展示，可折叠。
/// [expanded] 非 null = 受控模式（流式气泡，页面自动收起逻辑）；
/// null = 自管模式（历史消息，点标题展开/折叠）。
class _ThinkingPanel extends StatefulWidget {
  final String thinking;
  final bool live; // 思考进行中
  final double? secs; // 思考用时（完成后）
  final bool? expanded;
  final VoidCallback? onToggle;

  const _ThinkingPanel({
    required this.thinking,
    required this.live,
    this.secs,
    this.expanded,
    this.onToggle,
  });

  @override
  State<_ThinkingPanel> createState() => _ThinkingPanelState();
}

class _ThinkingPanelState extends State<_ThinkingPanel> {
  bool _own = false;

  bool get _expanded => widget.expanded ?? _own;

  void _toggle() {
    if (widget.expanded != null) {
      widget.onToggle?.call();
    } else {
      setState(() => _own = !_own);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final header = widget.live
        ? '思考中…'
        : (widget.secs != null
              ? '思考完成 · ${widget.secs!.toStringAsFixed(1)}s'
              : '思考内容');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.psychology_rounded, size: 13, color: cs.primary),
                const SizedBox(width: 4),
                Text(header, style: TextStyle(fontSize: 12, color: cs.outline)),
                Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 15,
                  color: cs.outline,
                ),
                if (widget.live) ...[
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 9,
                    height: 9,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: cs.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_expanded)
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 200),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              // 氛围模式不给看思考过程：既避免人格指令被看见，
              // 也省掉逐行打码；展开只给一句娇嗔
              child: SelectableText(
                Ambient.I.armed ? Ambient.I.thinkDeny : widget.thinking,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? leading;

  const GlassAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.leading,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(subtitle == null ? kToolbarHeight : kToolbarHeight + 14);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      // 顶栏玻璃：浅色 0.66 磨砂 + 底缘发丝线（纯透明等于没有玻璃）
      decoration: BoxDecoration(
        color: dark
            ? const Color(0xFF141A26).withValues(alpha: 0.62)
            : Colors.white.withValues(alpha: 0.66),
        border: Border(
          bottom: BorderSide(
            color: dark
                ? Colors.white.withValues(alpha: 0.10)
                : Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ),
      child: AppBar(
        backgroundColor: Colors.transparent,
        leading: leading,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: cs.outline),
              ),
          ],
        ),
        actions: actions,
        titleSpacing: 8,
        ),
    );
  }
}
