import 'dart:ui' show ImageFilter;

import 'dart:math' show Random, sin;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/ambient.dart';
import '../services/settings_service.dart';

/// iOS 26 玻璃风格容器：
/// 玻璃模式 = 高斯模糊 + 半透明材质 + 细描边；默认模式 = 常规卡片材质
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final Border? border;

  const GlassContainer({
    super.key,
    required this.child,
    this.radius = 18,
    this.padding,
    this.margin,
    this.color,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = Color(s.accentValue);

    if (s.styleMode != AppStyle.glass) {
      return Container(
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(radius),
          border:
              border ??
              Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: child,
      );
    }

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.35 : 0.07),
              blurRadius: dark ? 18 : 26,
              offset: Offset(0, dark ? 8 : 10),
              spreadRadius: dark ? 0 : -6,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          // ===== iOS 26 液态玻璃：三层折射 =====
          // 每层 = 模糊 + 微小平移（compose）：不同方向/幅度采样背景 →
          // 边缘出现真实的"折射错位"（玻璃厚度感来自位移差，不只是模糊）
          child: Stack(
            children: [
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.compose(
                    outer: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    inner: ImageFilter.matrix(
                      (Matrix4.identity()..translateByDouble(-1.6, -1.0, 0, 1))
                          .storage,
                    ),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.compose(
                    outer: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    inner: ImageFilter.matrix(
                      (Matrix4.identity()..translateByDouble(1.2, 1.6, 0, 1))
                          .storage,
                    ),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.compose(
                    outer: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
                    inner: ImageFilter.matrix(
                      (Matrix4.identity()..translateByDouble(0.6, -0.8, 0, 1))
                          .storage,
                    ),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              Container(
                padding: padding,
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  // 透镜边缘：顶缘高光带（0–30% 最亮，模拟光源折射）+
                  // 底缘极淡内阴影（玻璃厚度），alpha 全部压低避免冲淡内容
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: dark ? 0.14 : 0.30),
                      Colors.white.withValues(alpha: 0.0),
                      Colors.white.withValues(alpha: dark ? 0.02 : 0.04),
                      Colors.black.withValues(alpha: dark ? 0.10 : 0.025),
                    ],
                    stops: const [0, 0.30, 0.72, 1],
                  ),
                ),
                decoration: BoxDecoration(
                  // 色彩渗入：玻璃底色掺入主题色（模拟 saturate 提升的色彩感，
                  // Flutter 的 BackdropFilter 无 colorFilter，用 tint 补偿）
                  color:
                      color ??
                      Color.alphaBlend(
                        accent.withValues(alpha: dark ? 0.055 : 0.045),
                        dark
                            // iOS 26 玻璃 = 高度透明：背景色斑要透得过来
                            ? const Color(0xFF131926).withValues(alpha: 0.20)
                            : Colors.white.withValues(alpha: 0.24),
                      ),
                  borderRadius: BorderRadius.circular(radius),
                  border:
                      border ??
                      Border.all(
                        width: 1.1,
                        color: dark
                            ? Colors.white.withValues(alpha: 0.34)
                            : const Color(0x16111628),
                      ),
                ),
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 页面背景：
/// 玻璃模式 = 柔和渐变光斑；默认模式 = 主题背景色
class GlassWall extends StatelessWidget {
  final Widget child;
  const GlassWall({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (s.styleMode != AppStyle.glass) {
      // 默认模式：铺主题背景色，避免透明 Scaffold 透底
      // 背景彩虹必须是**静态**的（渐入后完全静止）：背景层在玻璃卡
      // BackdropFilter 的采样路径里，任何每帧变化都会逼全屏玻璃
      // 每帧重新模糊——"氛围一开就卡爆"的根因。动态流光看 AmbientRainbow。
      return ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Stack(
          children: [
            const Positioned.fill(child: _AmbientTintBackdrop()),
            Positioned.fill(child: child),
          ],
        ),
      );
    }
    final accent = Color(s.accentValue);
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? [
                        Color(0xFF0B0F1A),
                        Color.alphaBlend(
                          accent.withValues(alpha: 0.16),
                          const Color(0xFF0B0F1A),
                        ),
                        Color(0xFF0B0F1A),
                      ]
                    : [
                        const Color(0xFFF4F6FB),
                        Color.alphaBlend(
                          accent.withValues(alpha: 0.18),
                          Colors.white,
                        ),
                        const Color(0xFFEDF1F8),
                      ],
              ),
            ),
          ),
        ),
        // 色斑是"玻璃的可折射内容"：越多越浓，模糊/透镜边缘越明显
        // 右上那枚压在最上面（顶栏/玻璃条那一带），重了会像贴了一块图 → 淡一档
        Positioned(
          top: -90,
          right: -70,
          child: _blob(280, accent.withValues(alpha: dark ? 0.10 : 0.09)),
        ),
        Positioned(
          bottom: -90,
          left: -60,
          child: _blob(
            300,
            const Color(0xFF22D3EE).withValues(alpha: dark ? 0.09 : 0.10),
          ),
        ),
        Positioned(
          top: 190,
          left: -110,
          child: _blob(
            280,
            const Color(0xFFE91E8C).withValues(alpha: dark ? 0.05 : 0.06),
          ),
        ),
        Positioned(
          bottom: 120,
          right: -120,
          child: _blob(
            320,
            const Color(0xFF8B5CF6).withValues(alpha: dark ? 0.06 : 0.07),
          ),
        ),
        const Positioned.fill(child: _AmbientTintBackdrop()),
        Positioned.fill(child: child),
      ],
    );
  }

  /// 柔光色斑：多段 stops 收尾。
  /// 两段式（本色 → 全透明）的 alpha 是线性下落，圆边会留一圈看得见的弧线，
  /// 在浅色底上尤其像"贴了一张图"；四段让它外圈更快归零、边缘彻底化开。
  Widget _blob(double size, Color color) {
    final a = color.a;
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color,
              color.withValues(alpha: a * 0.52),
              color.withValues(alpha: a * 0.16),
              color.withValues(alpha: 0),
            ],
            stops: const [0, 0.34, 0.7, 1],
          ),
        ),
      ),
    );
  }
}

/// 氛围背景彩虹：armed 时渐入的**静态**粉彩彩虹底色。
/// 渐入完成即完全静止（玻璃模糊只多算这一次），之后零帧开销。
/// 每个实例随机相位，多层 GlassWall 嵌套时色相错开不显死板。
class _AmbientTintBackdrop extends StatefulWidget {
  const _AmbientTintBackdrop();

  @override
  State<_AmbientTintBackdrop> createState() => _AmbientTintBackdropState();
}

class _AmbientTintBackdropState extends State<_AmbientTintBackdrop> {
  late final double _phase = Random().nextDouble() * 6.283;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Ambient.I.tinted,
      builder: (context, on, _) {
        if (!on) return const SizedBox.shrink();
        // 渐入 400ms：期间玻璃模糊重算（一次性），结束后画面静止零开销
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          builder: (context, a, _) => RepaintBoundary(
            child: CustomPaint(
              size: Size.infinite,
              painter: _StaticRainbowPainter(a, _phase),
            ),
          ),
        );
      },
    );
  }
}

/// 静态彩虹底色：alpha 由渐入进度驱动（不随时间变化）
class _StaticRainbowPainter extends CustomPainter {
  final double a; // 渐入进度 0..1，完成后恒为 1
  final double phase;
  _StaticRainbowPainter(this.a, this.phase);

  static const _rainbow = <Color>[
    Color(0xFFFF6E9C), // 粉
    Color(0xFFFFA94C), // 杏
    Color(0xFFFFE066), // 柠
    Color(0xFF8CE0A4), // 薄荷
    Color(0xFF8CCBFF), // 天
    Color(0xFFC39CFF), // 紫
    Color(0xFFFF9ED9), // 玫
    Color(0xFFFF6E9C), // 闭环
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final base = 0.10 * a;

    final sweep = SweepGradient(
      startAngle: phase,
      endAngle: phase + 6.283,
      colors: [for (final c in _rainbow) c.withValues(alpha: base)],
      transform: const GradientRotation(-0.6),
    );
    canvas.drawRect(rect, Paint()..shader = sweep.createShader(rect));

    // 对角补光让角落也有颜色
    final aux = LinearGradient(
      begin: Alignment.bottomLeft,
      end: Alignment.topRight,
      colors: [
        const Color(0xFFFF9ED9).withValues(alpha: base * 0.6),
        Colors.transparent,
        const Color(0xFF8CCBFF).withValues(alpha: base * 0.6),
      ],
    );
    canvas.drawRect(rect, Paint()..shader = aux.createShader(rect));
  }

  @override
  bool shouldRepaint(covariant _StaticRainbowPainter old) =>
      old.a != a || old.phase != phase;
}

/// 氛围流光：armed 时罩在**全部内容之上**的极光带（_AppShake 挂载）。
/// 一条窄彩虹光带绕屏缓游——它不在任何 BackdropFilter 采样路径里，
/// 每帧动也只重画自己这一层（单 shader quad），玻璃模糊缓存不受影响。
class AmbientRainbow extends StatefulWidget {
  const AmbientRainbow({super.key});

  @override
  State<AmbientRainbow> createState() => _AmbientRainbowState();
}

class _AmbientRainbowState extends State<AmbientRainbow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: IgnorePointer(
        child: CustomPaint(size: Size.infinite, painter: _AuroraPainter(_c)),
      ),
    );
  }
}

/// 极光流光带：低透明度彩虹斜带缓慢巡游（可爱不糊字）
class _AuroraPainter extends CustomPainter {
  final Animation<double> t;
  _AuroraPainter(this.t) : super(repaint: t);

  static const _aurora = <Color>[
    Color(0x14FF6E9C),
    Color(0x14FFC49C),
    Color(0x14FFEFA4),
    Color(0x14A4E8BE),
    Color(0x14A4CCFF),
    Color(0x14C9A4FF),
    Color(0x14FF9ED9),
    Color(0x0014FF9E),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final v = t.value;
    // 光带沿对角线往返巡游（9s 一趟），端点略越界避免露边
    final span = size.width + size.height;
    final shift = (sin(v * 6.283) * 0.5 + 0.5) * span - span * 0.15;
    final band = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: _aurora,
      transform: GradientTranslation(shift),
    );
    canvas.drawRect(rect, Paint()..shader = band.createShader(rect));
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter oldDelegate) => true;
}

/// 把渐变平移 delta 像素（GradientTransform 实现，比改 begin/end 稳）
class GradientTranslation extends GradientTransform {
  final double delta;
  const GradientTranslation(this.delta);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(delta, -delta, 0);
}

/// 通用页面脚手架：背景墙覆盖全屏（含状态栏 + AppBar 区域，杜绝黑边）
class GlassScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;

  const GlassScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: floatingActionButton,
      body: GlassWall(
        child: Column(
          children: [
            // AppBar 画在背景墙之上（手动补状态栏高度）
            if (appBar != null)
              Padding(
                padding: EdgeInsets.only(
                  top: MediaQuery.paddingOf(context).top,
                ),
                child: appBar,
              ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}
