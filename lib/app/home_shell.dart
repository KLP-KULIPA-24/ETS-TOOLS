import 'dart:io';
import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart' show launchUrl, LaunchMode;

import '../pages/settings/achievements_page.dart';
import '../pages/modify/capture_page.dart';
import '../pages/ai/ai_chat_page.dart';
import '../pages/homework/homework_page.dart';
import '../pages/settings/settings_page.dart';
import '../services/ambient.dart';
import '../services/settings_service.dart';
import '../services/update_service.dart';
import '../widgets/glass.dart';
import '../widgets/mini_player.dart';
import '../widgets/tour_guide.dart';

/// 自适应外壳
/// Windows / 平板模式：左侧 NavigationRail；手机模式：底部悬浮胶囊（贴底）
/// 布局判定：自动（平板 shortestSide>=600dp 走左栏）或手动指定
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void dispose() {
    TourHub.request.removeListener(_onTourRequest);
    super.dispose();
  }

  void _onTourRequest() {
    final target = TourHub.request.value;
    TourHub.request.value = null;
    if (target == null || !mounted) return;
    setState(() => _index = target);
    // 等目标页 build 完、GlobalKey 挂上再弹蒙层
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 220), () {
        if (mounted) TourHub.show(context, target);
      });
    });
  }

  @override
  void initState() {
    super.initState();
    // 任何容器（如设置页）请求看某页教程 → 切过去并播放
    TourHub.request.addListener(_onTourRequest);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final pending = Ambient.I.popPendingFix;
      await Ambient.I.clearArmLast();
      if (!pending) return;
      await Ambient.I.markFxShown();
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(Ambient.I.fxTitle),
          content: Text(Ambient.I.fxBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(Ambient.I.fxBtn),
            ),
          ],
        ),
      );
    });
    // 启动时自动检测更新（设置里可关）：有新版本才提示，失败静默
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoCheckUpdate());
  }

  /// 静默查一次官网版本号；有更新就提示一次（联网失败不打扰用户）
  Future<void> _autoCheckUpdate() async {
    final s = SettingsService.I;
    if (!s.autoCheckUpdate) return;
    final r = await UpdateService.I.check();
    if (!mounted || !r.hasUpdate) return;
    final remote = r.remote;
    if (remote == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
        content: Text('发现新版本 V${remote.version}（当前 V${r.localVersion}）'),
        action: SnackBarAction(
          label: '去下载',
          onPressed: () => launchUrl(
            Uri.parse(remote.url),
            mode: LaunchMode.externalApplication,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const pages = [
      HomeworkPage(),
      AiChatPage(),
      CapturePage(),
      AchievementsPage(),
      SettingsPage(),
    ];
    const titles = ['作业', 'AI 对话', '修改', '成就', '设置'];
    final s = context.watch<SettingsService>();
    final autoTablet =
        MediaQuery.sizeOf(context).shortestSide >= 600 && Platform.isAndroid;
    final wide = switch (s.layoutMode) {
      UiLayoutMode.tablet => true,
      UiLayoutMode.mobile => false,
      UiLayoutMode.auto => Platform.isWindows || autoTablet,
    };

    return ValueListenableBuilder<bool>(
      valueListenable: Ambient.I.tinted,
      builder: (context, armed, _) {
        final body = Row(
          children: [
            if (wide) _buildRail(context, armed),
            if (wide) const VerticalDivider(width: 1),
            Expanded(child: pages[_index]),
          ],
        );

        // AppBar 画在背景墙内（背景墙全屏覆盖，杜绝顶部黑边）
        final mobileAppBar = AppBar(
          backgroundColor: Colors.transparent,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _logoBox(26, 8),
              const SizedBox(width: 8),
              const Text('E听说助手'),
              const SizedBox(width: 8),
              Text(
                titles[_index],
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(color: Theme.of(context).colorScheme.primary),
              ),
            ],
          ),
          actions: [_helpButton(context)],
        );

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              GlassWall(
                child: Column(
                  children: [
                    if (!wide)
                      Padding(
                        padding: EdgeInsets.only(
                          top: MediaQuery.paddingOf(context).top,
                        ),
                        child: mobileAppBar,
                      ),
                    Expanded(child: body),
                  ],
                ),
              ),
              // 手机模式：底部悬浮胶囊，强制贴底
              if (!wide)
                Positioned(
                  left: 14,
                  right: 14,
                  // 避让手机系统导航栏（edge-to-edge 下需手动留安全区）
                  bottom: 10 + MediaQuery.viewPaddingOf(context).bottom,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: _FloatingNavBar(
                        index: _index,
                        armed: armed,
                        onTap: (i) => setState(() => _index = i),
                      ),
                    ),
                  ),
                ),
              // 全局迷你播放条：任何位置点了播放都在这里暂停/拖动/关闭，
              // 返回上层页面也不断失控（手机避让底部悬浮胶囊）
              Positioned(
                left: 0,
                right: 0,
                bottom: wide
                    ? 20
                    : 86 + MediaQuery.viewPaddingOf(context).bottom,
                child: MiniPlayer(),
              ),
              // 氛围模式：到处乱跑的小图标（纯装饰，不挡操作）
              if (armed)
                const Positioned.fill(
                  child: IgnorePointer(child: _GhostIcons()),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 顶栏 / 侧栏共用的帮助入口：列出全部章节，点谁播谁
  Widget _helpButton(BuildContext context) => IconButton(
    tooltip: '使用教程',
    icon: const Icon(Icons.help_outline_rounded),
    onPressed: () => TourHub.showHelpSheet(context),
  );

  Widget _buildRail(BuildContext context, bool armed) {
    const dests = [
      (Icons.assignment_outlined, Icons.assignment_rounded, '作业'),
      (Icons.forum_outlined, Icons.forum_rounded, 'AI 对话'),
      (Icons.tune_outlined, Icons.tune_rounded, '修改'),
      (Icons.emoji_events_outlined, Icons.emoji_events_rounded, '成就'),
      (Icons.settings_outlined, Icons.settings_rounded, '设置'),
    ];
    return NavigationRail(
      backgroundColor: Colors.transparent,
      selectedIndex: _index,
      onDestinationSelected: (i) => setState(() => _index = i),
      labelType: NavigationRailLabelType.all,
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: _logoBox(40, 12),
      ),
      destinations: [
        for (var i = 0; i < dests.length; i++)
          NavigationRailDestination(
            icon: armed
                ? _Jitter(phase: i * 0.9, child: Icon(dests[i].$1))
                : Icon(dests[i].$1),
            selectedIcon: armed
                ? _Jitter(phase: i * 0.9, child: Icon(dests[i].$2))
                : Icon(dests[i].$2),
            label: Text(dests[i].$3),
          ),
      ],
      // 教程入口只在设置页顶部帮助卡里（用户要求：导航栏不放）
    );
  }

  Widget _logoBox(double size, double radius) {
    // 使用应用图标（assets/icon.png，由 tool/gen_assets.dart 生成）
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        'assets/icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF5B7CFF), Color(0xFF22D3EE)],
            ),
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Center(
            child: Text(
              'E',
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部悬浮胶囊（不透明度足够高，避免内容穿透干扰）
class _FloatingNavBar extends StatelessWidget {
  final int index;
  final bool armed;
  final ValueChanged<int> onTap;
  const _FloatingNavBar({
    required this.index,
    required this.armed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = context.watch<SettingsService>();
    final glass = s.styleMode == AppStyle.glass;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final items = const [
      (Icons.assignment_outlined, Icons.assignment_rounded, '作业'),
      (Icons.forum_outlined, Icons.forum_rounded, 'AI 对话'),
      (Icons.tune_outlined, Icons.tune_rounded, '修改'),
      (Icons.emoji_events_outlined, Icons.emoji_events_rounded, '成就'),
      (Icons.settings_outlined, Icons.settings_rounded, '设置'),
    ];

    Widget content = Container(
      height: 60,
      decoration: BoxDecoration(
        color: glass
            ? (dark
                  ? const Color(0xFF141A26).withValues(alpha: 0.92)
                  : Colors.white.withValues(alpha: 0.9))
            : cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(22),
        border: glass
            ? Border.all(
                color: dark
                    ? Colors.white.withValues(alpha: 0.14)
                    : Colors.white.withValues(alpha: 0.7),
              )
            : Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.4 : 0.14),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              // InkWell 涟漪：按下时立刻显示命中位置（整列热区），
              // 若涟漪与手指错位说明是系统触摸映射而非控件问题
              child: InkWell(
                onTap: () => onTap(i),
                splashColor: cs.primary.withValues(alpha: 0.16),
                highlightColor: Colors.transparent,
                child: SizedBox(
                  height: 60,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (armed)
                        _Jitter(
                          phase: i * 0.8,
                          child: Icon(
                            index == i ? items[i].$2 : items[i].$1,
                            size: 21,
                            color: index == i
                                ? cs.primary
                                : cs.onSurfaceVariant,
                          ),
                        )
                      else
                        Icon(
                          index == i ? items[i].$2 : items[i].$1,
                          size: 21,
                          color: index == i ? cs.primary : cs.onSurfaceVariant,
                        ),
                      const SizedBox(height: 2),
                      Text(
                        items[i].$3,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: index == i
                              ? FontWeight.w600
                              : FontWeight.w600,
                          color: index == i ? cs.primary : cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (glass) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: content,
        ),
      );
    }
    return content;
  }
}

/// 氛围模式：图标小幅跳动（纯装饰）
class _Jitter extends StatefulWidget {
  final Widget child;
  final double phase;
  const _Jitter({required this.child, this.phase = 0});

  @override
  State<_Jitter> createState() => _JitterState();
}

class _JitterState extends State<_Jitter> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 640),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final t = _c.value * 6.283 + widget.phase;
        return Transform.translate(
          offset: Offset(sin(t * 2.3) * 1.8, -sin(t * 3.1).abs() * 3.0),
          child: Transform.rotate(
            angle: sin(t * 2.7) * 0.11,
            child: widget.child,
          ),
        );
      },
    );
  }
}

class _Ghost {
  final IconData? icon; // 非 null 时画 Material 图标
  final String? mark; // 非 null 时画字符（♪★✿ 之类）
  final Color color; // 糖果粉彩色，每只固定
  final double alpha; // 固定透明度档位（进排版缓存键，绝不能每帧变）
  double x, y, vx, vy, size, rot, vr, phase;
  _Ghost({
    this.icon,
    this.mark,
    required this.color,
    required this.alpha,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.rot,
    required this.vr,
    required this.phase,
  });
}

/// 氛围模式：到处乱跑的可爱小元素（不挡操作、不发声）。
/// 性能关键：所有元素画在**一个** CustomPaint 上（单 Ticker 只更新数据、
/// painter 以 controller 为 repaint listenable），整层一个 RepaintBoundary。
/// 旧版是 14 个 Positioned widget 每帧 setState 重建整棵子树，这是卡顿源之一。
class _GhostIcons extends StatefulWidget {
  const _GhostIcons();

  @override
  State<_GhostIcons> createState() => _GhostIconsState();
}

class _GhostIconsState extends State<_GhostIcons>
    with SingleTickerProviderStateMixin {
  // 可爱系图标：爱心/星星/音符/蛋糕/冰淇淋/调色板/笑脸/魔法
  static const _icons = [
    Icons.favorite_rounded,
    Icons.star_rounded,
    Icons.music_note_rounded,
    Icons.cake_rounded,
    Icons.icecream_rounded,
    Icons.palette_rounded,
    Icons.sentiment_very_satisfied_rounded,
    Icons.auto_awesome,
  ];

  // 乱飞的字符（拟人化的"手忙脚乱"感 + 花与闪光）
  static const _marks = ['♪', '★', '✿', '❀', '✧', '?', '!', '…'];

  // 糖果粉彩（比主题色更"彩虹"）
  static const _candy = [
    Color(0xFFFF6E9C), // 粉
    Color(0xFFFFA94C), // 杏
    Color(0xFFFFD84C), // 黄
    Color(0xFF7BD88F), // 绿
    Color(0xFF6EB5FF), // 蓝
    Color(0xFFB58CFF), // 紫
    Color(0xFFFF8CD9), // 玫
  ];

  final _rnd = Random();
  final List<_Ghost> _ghosts = [];
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _spawn(Size size) {
    for (var i = 0; i < 18; i++) {
      final isMark = i >= _icons.length;
      _ghosts.add(
        _Ghost(
          icon: isMark ? null : _icons[i % _icons.length],
          mark: isMark ? _marks[i % _marks.length] : null,
          color: _candy[_rnd.nextInt(_candy.length)],
          alpha: [0.45, 0.55, 0.65][_rnd.nextInt(3)],
          x: _rnd.nextDouble() * (size.width - 60) + 20,
          y: _rnd.nextDouble() * (size.height - 60) + 20,
          vx: (_rnd.nextBool() ? 1 : -1) * (1.2 + _rnd.nextDouble() * 2.2),
          vy: (_rnd.nextBool() ? 1 : -1) * (1.2 + _rnd.nextDouble() * 2.2),
          size: 18 + _rnd.nextDouble() * 16,
          rot: _rnd.nextDouble() * 6.28,
          vr: (_rnd.nextBool() ? 1 : -1) * 0.035,
          phase: _rnd.nextDouble() * 6.28,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        if (_ghosts.isEmpty && size.width > 60) _spawn(size);
        return RepaintBoundary(
          child: CustomPaint(size: size, painter: _GhostPainter(_ghosts, _c)),
        );
      },
    );
  }
}

/// 一次 paint 画完全部幽灵；controller 只作 repaint 信号，
/// 位置积分、摆动、旋转都在 paint 里按 dt 推进。
class _GhostPainter extends CustomPainter {
  final List<_Ghost> ghosts;
  final Animation<double> t;

  _GhostPainter(this.ghosts, this.t) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || ghosts.isEmpty) return;
    final dt = _dt();
    for (final g in ghosts) {
      // 边界反弹（含 wobble 幅度余量）
      final wob = 3.0;
      g.x += g.vx * dt;
      g.y += g.vy * dt;
      g.rot += g.vr * dt;
      if (g.x < wob || g.x > size.width - g.size - wob) {
        g.vx = -g.vx;
        g.x = g.x.clamp(wob, size.width - g.size - wob);
      }
      if (g.y < wob || g.y > size.height - g.size - wob) {
        g.vy = -g.vy;
        g.y = g.y.clamp(wob, size.height - g.size - wob);
      }
      // 呼吸摆动：让轨迹带一点波浪，不那么机械；
      // "呼吸"用 canvas 缩放实现（不进排版缓存键，TextPainter 可复用）
      final tt = t.value * 6.283 * 4 + g.phase;
      final dx = g.x + sin(tt) * wob;
      final dy = g.y + cos(tt * 1.3) * wob;

      canvas.save();
      canvas.translate(dx + g.size / 2, dy + g.size / 2);
      canvas.rotate(g.rot);
      final breathe = 1.0 + 0.08 * sin(tt * 0.7);
      canvas.scale(breathe);
      final tp = _layout(g);
      tp.paint(canvas, Offset(-g.size / 2, -g.size / 2));
      canvas.restore();
    }
  }

  final Map<String, TextPainter> _cache = {};

  /// 排版缓存：键只含稳定量（图形/字号/颜色/固定透明度档位）。
  /// ⚠️ 千万别把每帧变化的值放进键——上版把呼吸 alpha 放进来了，
  /// 缓存永久 miss，每帧 18 次 TextPainter.layout 且 Map 无限增长。
  TextPainter _layout(_Ghost g) {
    final key =
        '${g.icon?.codePoint ?? g.mark}|${g.size.round()}|${g.color.toARGB32()}';
    return _cache.putIfAbsent(key, () {
      final style = g.icon != null
          ? TextStyle(
              fontFamily: g.icon!.fontFamily,
              package: g.icon!.fontPackage,
              fontSize: g.size,
              color: g.color.withValues(alpha: g.alpha),
            )
          : TextStyle(
              fontSize: g.size * 0.95,
              fontWeight: FontWeight.w600,
              color: g.color.withValues(alpha: g.alpha),
              height: 1.0,
            );
      return TextPainter(
        text: TextSpan(
          text: g.icon != null
              ? String.fromCharCode(g.icon!.codePoint)
              : g.mark ?? '?',
          style: style,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  double _prev = 0;

  /// 6s 一圈的 controller → 秒级 dt（限幅防切后台回来跳变）
  double _dt() {
    final now = t.value * 6.0;
    final d = (now - _prev).clamp(0.0, 0.1);
    _prev = now;
    return d * 60; // 归一化到"60fps 帧"单位，速度参数按旧版帧步长沿用
  }

  @override
  bool shouldRepaint(covariant _GhostPainter oldDelegate) => true;
}
