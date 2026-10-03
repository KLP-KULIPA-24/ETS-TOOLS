/// Android 悬浮窗入口：默认收缩为软件图标，点击平滑展开功能面板
/// 面板菜单：答案 / AI 实时快问（流式）/ 修改 / 播放控制
library;

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'services/ai_chat_service.dart';
import 'services/ai_service.dart';
import 'services/audio_player_service.dart';
import 'services/floating_bridge.dart';
import 'services/settings_service.dart';
import 'widgets/style.dart';

@pragma("vm:entry-point")
void overlayMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsService.I.load();
  runApp(const OverlayApp());
}

class OverlayApp extends StatelessWidget {
  const OverlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: OverlayHome(),
    );
  }
}

class OverlayHome extends StatefulWidget {
  const OverlayHome({super.key});

  @override
  State<OverlayHome> createState() => _OverlayHomeState();
}

class _OverlayHomeState extends State<OverlayHome> {
  bool expanded = false;
  String _tab = 'answers';
  String _title = '';
  String _answers = '';
  final _ctrl = TextEditingController();
  bool _sending = false;
  String _reply = '';

  @override
  void initState() {
    super.initState();
    _load();
    FlutterOverlayWindow.overlayListener.listen((_) => _load());
  }

  Future<void> _load() async {
    final p = await FloatingBridge.load();
    if (mounted) {
      setState(() {
        _title = p.title;
        _answers = p.answers;
      });
    }
  }

  Future<void> _toggle() async {
    setState(() => expanded = !expanded);
    final size = MediaQuery.of(context).size;
    if (expanded) {
      await FlutterOverlayWindow.resizeOverlay(
        size.width.toInt(),
        (size.height * 0.72).toInt(),
        true,
      );
    } else {
      await FlutterOverlayWindow.resizeOverlay(120, 120, true);
    }
  }

  Future<void> _ask() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    if (!SettingsService.I.aiReady) {
      setState(() => _reply = '请先到设置配置 AI');
      return;
    }
    setState(() {
      _sending = true;
      _reply = '';
    });
    try {
      final history = [
        ChatMsg(role: 'user', text: '当前作业：$_title\n内容：$_answers'),
        ChatMsg(role: 'user', text: text),
      ];
      final req = AiChatService.I.buildRequest(
        history: history,
        contextTitle: _title,
      );
      final buf = StringBuffer();
      await AiService.I.chatWithFailover(
        messages: req,
        onDelta: (d) {
          buf.write(d);
          if (mounted) setState(() => _reply = buf.toString());
        },
      );
      _reply = buf.toString();
    } catch (e) {
      _reply = '调用失败：$e';
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!expanded) {
      // 收缩态：仅软件图标
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: GestureDetector(
            onTap: _toggle,
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF5B7CFF).withValues(alpha: 0.45),
                    blurRadius: 18,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Image.asset('assets/icon.png', fit: BoxFit.cover),
              ),
            ),
          ),
        ),
      );
    }

    // 展开面板
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        child: LiquidGlass(
          radius: BorderRadius.circular(24),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Image.asset(
                      'assets/icon.png',
                      width: 22,
                      height: 22,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _title.isEmpty ? 'E听说助手 · 悬浮窗' : _title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '收起为图标',
                    onPressed: _toggle,
                    icon: const Icon(Icons.minimize_rounded, size: 18),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '关闭悬浮窗',
                    onPressed: () => FlutterOverlayWindow.closeOverlay(),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
              // 功能菜单
              Row(
                children: [
                  _menuChip(context, 'answers', Icons.assignment_rounded, '答案'),
                  const SizedBox(width: 6),
                  _menuChip(context, 'chat', Icons.forum_rounded, 'AI'),
                  const SizedBox(width: 6),
                  _menuChip(context, 'tweak', Icons.tune_rounded, '修改'),
                ],
              ),
              const Divider(height: 12),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: switch (_tab) {
                    'chat' => _chatTab(context),
                    'tweak' => _tweakTab(context),
                    _ => _answersTab(context),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuChip(
    BuildContext context,
    String id,
    IconData icon,
    String label,
  ) {
    final cs = Theme.of(context).colorScheme;
    final active = _tab == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? cs.primary.withValues(alpha: 0.16)
                : cs.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: active ? cs.primary : Colors.transparent),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: active ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.bold : FontWeight.w600,
                  color: active ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _answersTab(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('answers'),
      child: Text(
        _answers.isEmpty ? '（无推送答案）' : _answers,
        style: const TextStyle(fontSize: 13, height: 1.6),
      ),
    );
  }

  Widget _chatTab(BuildContext context) {
    return Column(
      key: const ValueKey('chat'),
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Text(
              _reply.isEmpty ? '输入问题，AI 将结合当前作业回答。' : _reply,
              style: const TextStyle(fontSize: 13, height: 1.6),
            ),
          ),
        ),
        Row(
          children: [
            IconButton(
              tooltip: '播放 / 暂停',
              onPressed: () => AudioPlayerService.I.toggle(),
              icon: const Icon(Icons.play_circle_outline_rounded, size: 20),
            ),
            Expanded(
              child: TextField(
                controller: _ctrl,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '问 AI…',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _ask(),
              ),
            ),
            IconButton(
              onPressed: _sending ? null : _ask,
              icon: _sending
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded, size: 20),
            ),
          ],
        ),
      ],
    );
  }

  Widget _tweakTab(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      key: const ValueKey('tweak'),
      children: [
        ListTile(
          dense: true,
          leading: Icon(Icons.tune_rounded, color: cs.primary),
          title: const Text('打开修改栏', style: TextStyle(fontSize: 13)),
          subtitle: const Text(
            '在主界面「修改」页配置抓包拦截',
            style: TextStyle(fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => FlutterOverlayWindow.closeOverlay(),
        ),
        ListTile(
          dense: true,
          leading: Icon(Icons.info_outline_rounded, color: cs.primary),
          title: const Text('拦截引擎待接入', style: TextStyle(fontSize: 13)),
          subtitle: const Text('抓包数据提供后自动启用', style: TextStyle(fontSize: 12)),
          trailing: Icon(
            Icons.hourglass_empty_rounded,
            size: 18,
            color: cs.outline,
          ),
        ),
      ],
    );
  }
}
