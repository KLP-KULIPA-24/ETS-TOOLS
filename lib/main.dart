// 托盘使用 tray_manager 0.7 的 legacy 桥接层（官方维护的过渡 API）
// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:tray_manager/legacy.dart' as tray;
import 'package:window_manager/window_manager.dart';

import 'app/home_shell.dart';
import 'widgets/glass.dart';
import 'pages/settings/onboarding_page.dart';
import 'widgets/style.dart';
import 'services/achievements.dart';
import 'services/ambient.dart';
import 'services/capture_engine.dart';
import 'services/capture_system.dart';
import 'services/floating_bridge.dart';
// 必须 import：未被引用的 Dart 文件不会进编译产物，
// AOT 快照里将缺少 overlayMain 入口，安卓悬浮窗引擎启动必失败
//（logcat: Could not resolve main entrypoint function）
// ignore: unused_import
import 'overlay_main.dart';
import 'services/audio_player_service.dart';
import 'services/tts_service.dart';
import 'services/demo_service.dart';
import 'services/ets_data_service.dart';
import 'services/settings_service.dart';
import 'services/tray_menu_service.dart';
import 'services/hotkey_channel.dart';

/// 桌面（Windows）视频控件主题：进度条/拖块用应用主题色
MaterialDesktopVideoControlsThemeData _desktopControlsTheme(Color accent) =>
    MaterialDesktopVideoControlsThemeData(
      seekBarPositionColor: accent,
      seekBarThumbColor: accent,
      seekBarBufferColor: Colors.white.withValues(alpha: 0.30),
      seekBarColor: Colors.white.withValues(alpha: 0.22),
      seekBarHeight: 4.0,
    );

/// 视频控件主题：进度条/拖块用应用主题色（media_kit 默认是红色）
MaterialVideoControlsThemeData _videoControlsTheme(Color accent) =>
    MaterialVideoControlsThemeData(
      seekBarPositionColor: accent,
      seekBarThumbColor: accent,
      seekBarBufferColor: Colors.white.withValues(alpha: 0.30),
      seekBarColor: Colors.white.withValues(alpha: 0.22),
      seekBarHeight: 3.5,
    );

/// 返回上一级即停止朗读：pop 时停音频与 TTS。
/// 退出软件到后台 / 锁屏不触发 pop，播放继续。
class _StopAudioOnPop extends NavigatorObserver {
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    AudioPlayerService.I.stop();
    TtsService.I.stop();
  }
}

final _stopOnPopObserver = _StopAudioOnPop();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 视频引擎初始化（模仿朗读考试视频）：**全平台必须调用**，
  // 只在 Windows 初始化会让 Android 端 new Player() 直接抛
  // "MediaKit.ensureInitialized must be called" → 视频区灰块
  MediaKit.ensureInitialized();

  await SettingsService.I.load();
  await Achievements.init();
  // 修改模块：加载满分知识库、恢复上次残留的系统代理、后台预热 CA
  unawaited(CaptureEngine.I.init());
  if (DateTime.now().hour < 5) {
    Achievements.unlock('night_owl');
  }
  await Ambient.I.loadFx();
  // 首启准备内置演示作业（教程完成后自动隐藏）
  if (!SettingsService.I.onboardDone) {
    await DemoService.prepare();
  }

  if (Platform.isAndroid) {
    // 全面屏：透明状态栏/导航栏，消除顶部黑边
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
  }

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    const opts = WindowOptions(
      title: 'E听说助手',
      size: Size(1180, 760),
      minimumSize: Size(920, 560),
      center: true,
      titleBarStyle: TitleBarStyle.hidden,
    );
    await windowManager.waitUntilReadyToShow(opts, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    // 关闭窗口 = 退出进程，此时必须还原系统代理，否则整机断网
    windowManager.setPreventClose(false);
    windowManager.addListener(_WindowCloseGuard());
    await _trayCtl.init();
    // 电脑端：窗口置顶 + Ctrl+Alt+E 全局快捷键（设置页可开关）
    final s0 = SettingsService.I;
    await windowManager.setAlwaysOnTop(s0.alwaysOnTop);
    await HotkeyChannel.init(enabled: s0.hotkeyToggle);
  }

  runApp(const EtsHelperApp());
}

/// 托盘：软件图标；氛围模式时图标在粉调变体间跳动
class _TrayCtl with tray.TrayListener {
  Timer? _cycle;

  Future<void> init() async {
    tray.TrayManager.instance.addListener(this);
    await tray.TrayManager.instance.setIcon('assets/icon.png');
    await tray.TrayManager.instance.setToolTip('E听说助手');
    // Windows 走自绘玻璃弹窗（C++ tray_menu），其余平台用系统菜单
    if (TrayMenuService.supported) {
      TrayMenuService.init(onPicked: _onMenuPicked);
    } else {
      await tray.TrayManager.instance.setContextMenu(
        tray.Menu(
          items: [
            tray.MenuItem(key: 'show', label: '打开主窗口'),
            tray.MenuItem.separator(),
            tray.MenuItem(key: 'exit', label: '退出'),
          ],
        ),
      );
    }
    Ambient.I.tinted.addListener(_onTint);
  }

  /// 玻璃菜单点击：0=打开主窗口，2=退出（1 是分隔线）
  void _onMenuPicked(int index) {
    if (index == 0) {
      windowManager.show();
      windowManager.focus();
    } else if (index == 2) {
      _quit();
    }
  }

  /// 退出前必须还原系统代理：软件一关而代理还指着引擎 = 整机断网
  Future<void> _quit() async {
    // 代理还原必须完成（否则残留代理 = 断网），但它要跑几条 reg 子进程，
    // 顺序等待会让"点退出后半天不关"（用户反馈）→ 与关窗并行，最多等 1.2s
    final cleanup = () async {
      try {
        await CaptureEngine.I.stop();
        await CaptureSystem.proxyRestoreIfOurs();
      } catch (_) {}
    }();
    await Future.any([
      cleanup,
      Future<void>.delayed(const Duration(milliseconds: 1200)),
    ]);
    await windowManager.destroy();
  }

  void _onTint() {
    if (Ambient.I.tinted.value) {
      windowManager.setTitle(Ambient.I.titleArmed);
      const icons = [
        'assets/tray/icon_rose.png',
        'assets/tray/icon_blossom.png',
      ];
      var i = 0;
      tray.TrayManager.instance.setIcon(icons[0]);
      _cycle?.cancel();
      _cycle = Timer.periodic(const Duration(milliseconds: 900), (_) {
        i = (i + 1) % icons.length;
        tray.TrayManager.instance.setIcon(icons[i]);
      });
    } else {
      windowManager.setTitle(Ambient.I.titleNormal);
      _cycle?.cancel();
      tray.TrayManager.instance.setIcon('assets/icon.png');
    }
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  /// 右键：直接用 Windows 系统托盘菜单（自绘玻璃菜单在本机始终不显示，
  /// 用户定夺 → 回归系统菜单，稳定第一）
  @override
  Future<void> onTrayIconRightMouseDown() async {
    await tray.TrayManager.instance.setContextMenu(
      tray.Menu(
        items: [
          tray.MenuItem(key: 'show', label: '打开主窗口'),
          tray.MenuItem.separator(),
          tray.MenuItem(key: 'exit', label: '退出'),
        ],
      ),
    );
    await tray.TrayManager.instance.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(tray.MenuItem menuItem) {
    if (menuItem.key == 'show') {
      windowManager.show();
      windowManager.focus();
    } else if (menuItem.key == 'exit') {
      _quit();
    }
  }
}

final _trayCtl = _TrayCtl();

/// 窗口关闭（= 进程退出）前还原系统代理与引擎
class _WindowCloseGuard with WindowListener {
  @override
  void onWindowClose() {
    unawaited(() async {
      try {
        await CaptureEngine.I.stop();
        await CaptureSystem.proxyRestoreIfOurs();
      } catch (_) {}
    }());
  }
}

/// 全局窗口壳：自绘标题栏（悬浮模式与移动端不显示）
class _WindowChrome extends StatelessWidget {
  final Widget child;
  const _WindowChrome({required this.child});

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows) return child;
    return ValueListenableBuilder<bool>(
      valueListenable: FloatingBridge.inFloating,
      builder: (context, floating, _) {
        if (floating) return child;
        return Column(
          children: [
            const _TitleBar(),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}

class _TitleBar extends StatefulWidget {
  const _TitleBar();

  @override
  State<_TitleBar> createState() => _TitleBarState();
}

class _TitleBarState extends State<_TitleBar> with WindowListener {
  bool _max = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _refreshMax();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _max = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _max = false);
  }

  Future<void> _toggleMax() async {
    if (_max) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
    await _refreshMax();
  }

  Future<void> _refreshMax() async {
    final m = await windowManager.isMaximized();
    if (mounted) setState(() => _max = m);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onDoubleTap: _toggleMax,
      child: DragToMoveArea(
        child: Container(
          height: 36,
          color: dark ? const Color(0xFF12151C) : const Color(0xFFEFF3FF),
          child: Row(
            children: [
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: Image.asset(
                  'assets/icon.png',
                  width: 18,
                  height: 18,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'E听说助手',
                style: TextStyle(fontSize: 12, color: cs.onSurface),
              ),
              const Spacer(),
              _WinBtn(
                icon: Icons.minimize_rounded,
                onTap: windowManager.minimize,
              ),
              _WinBtn(
                icon: _max
                    ? Icons.filter_center_focus_rounded
                    : Icons.crop_square_rounded,
                onTap: _toggleMax,
              ),
              _WinBtn(
                icon: Icons.close_rounded,
                danger: true,
                onTap: windowManager.close,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WinBtn extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;
  const _WinBtn({required this.icon, required this.onTap, this.danger = false});

  @override
  State<_WinBtn> createState() => _WinBtnState();
}

class _WinBtnState extends State<_WinBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 42,
          height: 36,
          color: _hover
              ? (widget.danger
                    ? Colors.red.withValues(alpha: 0.85)
                    : cs.onSurface.withValues(alpha: 0.08))
              : Colors.transparent,
          child: Icon(
            widget.icon,
            size: 16,
            color: _hover && widget.danger ? Colors.white : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 氛围模式：界面抖动 + 全局彩虹滤镜（armed 门控）。
///
/// 性能铁律（2026-09-30 "卡爆"事故的结论）：
/// 1. 抖动必须是**脉冲式**——每 2.2s 抖 ~0.3s，其余时间 offset 归零、
///    画面完全静止，引擎的 raster cache 才能命中（页面里几十张玻璃卡的
///    BackdropFilter 只有在输入完全不变时才被缓存）。
/// 2. 彩虹滤镜必须罩在**内容之上**——放背景层就进了 BackdropFilter 的
///    采样路径，每帧旋转会逼全屏玻璃每帧重新模糊。
/// 3. 全窗口 setPosition 是系统级操作（DWM 重合成 + 重新光栅化），
///    连续 50ms 一次等同每秒 20 次全树重绘，只允许脉冲期间短促使用。
class _AppShake extends StatefulWidget {
  final Widget? child;
  const _AppShake({required this.child});

  @override
  State<_AppShake> createState() => _AppShakeState();
}

class _AppShakeState extends State<_AppShake>
    with SingleTickerProviderStateMixin {
  // 打嗝式节奏：一个周期 0.9s，前 22% (~200ms) 是抖动脉冲（渐弱两下），
  // 其余完全静止让引擎缓存生效——持续有"抽搐"的节奏感，占空比只有两成
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  Timer? _winShake;
  int _gen = 0; // 脉冲代际：解除氛围时让进行中的窗口抖动序列自行终止

  @override
  void initState() {
    super.initState();
    Ambient.I.tinted.addListener(_onTint);
  }

  @override
  void dispose() {
    Ambient.I.tinted.removeListener(_onTint);
    _gen++;
    _winShake?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _onTint() {
    if (Ambient.I.tinted.value) {
      _startWinShake();
    } else {
      _stopWinShake();
    }
  }

  /// 窗口抖动脉冲：与内容抖动同节奏（每 0.9s 抖 4 步并归位）。
  /// 不再连续 setPosition——那是系统级移动，连续做等于每秒 20 次全树重绘。
  Future<void> _startWinShake() async {
    if (!Platform.isWindows || FloatingBridge.inFloating.value) return;
    if (await windowManager.isMaximized()) return;
    _winShake?.cancel();
    final gen = ++_gen;
    _winShake = Timer.periodic(const Duration(milliseconds: 900), (_) {
      _winPulse(gen);
    });
    // 触发瞬间先来一轮，不用等 0.9s
    _winPulse(gen);
  }

  Future<void> _winPulse(int gen) async {
    // 锚点每轮 fresh 取：用户拖动过窗口就以新位置为中心，
    // 否则下一轮会把窗口拽回触发时的旧位置（已踩过的 bug）
    final anchor = await windowManager.getPosition();
    // 3 步（原 4 步）、幅度略收：窗口移动 = DWM 重合成，次数越少越顺
    for (var i = 0; i < 3; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (gen != _gen || !Ambient.I.armed) return;
      final t = i / 3 * 6.283;
      await windowManager.setPosition(
        anchor + Offset(sin(t * 3) * 3.0, sin(t * 2.2) * 2.6),
      );
    }
    if (gen != _gen || !Ambient.I.armed) return;
    await windowManager.setPosition(anchor);
  }

  void _stopWinShake() {
    _gen++;
    _winShake?.cancel();
    _winShake = null;
    // 不恢复任何"旧位置"——脉冲每轮自归位，这里再 setPosition 反而抢窗口
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Ambient.I.tinted,
      builder: (context, armed, child) {
        if (!armed) return child ?? const SizedBox.shrink();
        return Stack(
          children: [
            // 内容层：脉冲式抖动（静止期 offset 恒为零，缓存全命中）
            AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final v = _c.value;
                const pulse = 0.22;
                var off = Offset.zero;
                if (v < pulse) {
                  final p = v / pulse; // 0..1
                  final decay = 1 - p; // 渐弱：抖两下停住
                  off = Offset(
                    sin(p * 6.283 * 2) * 4.6 * decay,
                    cos(p * 6.283 * 1.6) * 3.8 * decay,
                  );
                }
                return Transform.translate(
                  offset: off,
                  child: RepaintBoundary(child: child),
                );
              },
            ),
            // 彩虹滤镜罩在最上层：不进玻璃模糊采样路径，玻璃缓存不受影响
            const Positioned.fill(
              child: IgnorePointer(child: AmbientRainbow()),
            ),
          ],
        );
      },
      child: widget.child,
    );
  }
}

class EtsHelperApp extends StatelessWidget {
  const EtsHelperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: SettingsService.I),
        ChangeNotifierProvider.value(value: EtsDataService.I),
        ChangeNotifierProvider.value(value: AudioPlayerService.I),
      ],
      child: Consumer<SettingsService>(
        builder: (context, s, _) {
          return MaterialApp(
            navigatorKey: Achievements.navigatorKey,
            // 返回上一级页面即停止朗读/TTS；退出软件到后台或锁屏不受影响（无 pop 发生）
            navigatorObservers: [_stopOnPopObserver],
            title: 'E听说助手',
            debugShowCheckedModeBanner: false,
            themeMode: s.themeMode,
            // 浅色/深色各自生成 ColorScheme：一套 scheme 喂两个 ThemeData 会
            // 因 brightness 不匹配触发 ThemeData 断言（debug 崩溃）
            theme: _theme(
              ColorScheme.fromSeed(
                seedColor: Color(s.accentValue),
                brightness: Brightness.light,
              ),
              Brightness.light,
            ),
            darkTheme: _theme(
              ColorScheme.fromSeed(
                seedColor: Color(s.accentValue),
                brightness: Brightness.dark,
              ),
              Brightness.dark,
            ),
            home: s.onboardDone ? const HomeShell() : const OnboardingPage(),
            builder: (context, child) => _WindowChrome(
              // 视频控件主题色（媒体进度条等）：
              // 必须在这里全局提供——全屏播放是新路由，VideoCard 的局部
              // 主题继承不到，会退回 media_kit 默认的红色(0xFFFF0000)
              child: MaterialVideoControlsTheme(
                normal: _videoControlsTheme(Color(s.accentValue)),
                fullscreen: _videoControlsTheme(Color(s.accentValue)),
                // ⚠️ 桌面（Windows）走的是 *Desktop* 控件主题：不设这个，
                // 桌面端进度条会用 media_kit 默认的红色（用户反馈）
                child: MaterialDesktopVideoControlsTheme(
                  normal: _desktopControlsTheme(Color(s.accentValue)),
                  fullscreen: _desktopControlsTheme(Color(s.accentValue)),
                  child: _AppShake(child: child),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  ThemeData _theme(ColorScheme scheme, Brightness b) {
    // docs/style-pack/tokens.json：surface/border/text 深色为规范值，浅色派生
    final surface = StyleTokens.surfaceOf(b);
    final borderColor = StyleTokens.borderOf(b);
    final themed = scheme.copyWith(
      surface: surface,
      surfaceContainerLowest: surface,
      outlineVariant: borderColor,
      // M3 默认 outline 在浅色下过淡（设置页图标/副标题大量使用 → 灰蒙蒙）：
      // 显式定制为"仍浅但看得清"的灰蓝
      outline: b == Brightness.dark
          ? const Color(0xFF8A93A3)
          : const Color(0xFF6B7383),
      onSurfaceVariant: b == Brightness.dark
          ? const Color(0xFF9AA1AC)
          : const Color(0xFF525A68),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: themed,
      brightness: b,
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: StyleTokens.textOf(b),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: StyleTokens.textOf(b),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor.withValues(alpha: 0.7)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: surface,
        elevation: 8,
        showDragHandle: true,
        dragHandleColor: borderColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: 0.14),
        elevation: 0,
        height: 64,
      ),
      dividerTheme: DividerThemeData(
        color: borderColor,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        // iOS 26 质感：胶囊、无硬边。选中态给**实色**主题色 + 白字——
        // 此前是 primary@0.14 的淡染，全屏没有一处实色落点，
        // 主题色一进界面就被稀释成灰，整页读作"灰蒙蒙"的根因之一。
        backgroundColor: StyleTokens.textOf(b).withValues(alpha: 0.06),
        selectedColor: themed.primary,
        checkmarkColor: Colors.white,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        // 选中态文字：FilterChip/ChoiceChip 的 M3 默认会解析成
        // onSecondaryContainer（深色），压在实色主题色上读不清——各 FilterChip
        // 的 label 已按 selected 显式给白。这里保持普通深色样式即可，
        // 不要用 MaterialStateTextStyle（会让未选中 chip 的文字被解析成白色）。
        labelStyle: TextStyle(
          fontSize: AppText.sm,
          fontWeight: AppText.wMedium,
          color: StyleTokens.textOf(b),
        ),
        secondaryLabelStyle: TextStyle(
          fontSize: AppText.sm,
          fontWeight: AppText.wBold,
          color: Colors.white,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const StadiumBorder(),
          foregroundColor: themed.primary,
          textStyle: const TextStyle(fontSize: 13),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStatePropertyAll(8),
        radius: const Radius.circular(999),
        thumbColor: WidgetStatePropertyAll(
          StyleTokens.textOf(b).withValues(alpha: 0.22),
        ),
      ),
      // 输入框：iOS 胶囊——浅灰填充、无硬边、圆角 999
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: StyleTokens.textOf(b).withValues(alpha: 0.05),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: AppSpace.md,
        ),
        hintStyle: TextStyle(
          fontSize: AppText.md,
          color: StyleTokens.textMutedOf(b).withValues(alpha: 0.7),
        ),
        border: const OutlineInputBorder(
          borderRadius: AppRadius.capsule,
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: AppRadius.capsule,
          borderSide: BorderSide.none,
        ),
        // 聚焦时给**实色**主题色描边（components.md：focus 变 primary、不加外发光）
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.capsule,
          borderSide: BorderSide(color: themed.primary, width: 1.5),
        ),
      ),
      // 控件胶囊形（style-pack: control = capsule）+ 轻透底，替掉默认 Material 硬边按钮
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          elevation: 0,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          side: BorderSide(color: themed.primary.withValues(alpha: 0.28)),
          backgroundColor: themed.primary.withValues(alpha: 0.06),
          foregroundColor: StyleTokens.textOf(b),
          textStyle: const TextStyle(fontSize: 13),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(shape: const StadiumBorder()),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        shape: StadiumBorder(),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        // 轻透玻璃底，不再是实心黑块
        backgroundColor: StyleTokens.textOf(b).withValues(alpha: 0.74),
        elevation: 0,
        contentTextStyle: TextStyle(
          fontSize: 13,
          color: b == Brightness.dark ? const Color(0xFF0F1115) : Colors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        ),
        // 底部抬到导航胶囊之上，不再压住下方菜单栏
        insetPadding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
      ),
    );
  }
}
