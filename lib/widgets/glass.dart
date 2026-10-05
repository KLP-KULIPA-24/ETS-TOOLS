import 'dart:typed_data' show Float64List;
import 'dart:ui' show ImageFilter;

import 'dart:math' show Random, sin;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/ambient.dart';
import '../services/settings_service.dart';

/// 饱和度滤镜（等价于 CSS 的 `saturate(180%)`）。
///
/// 这是网页版每个玻璃件都带的一步，也是 App 端长期缺的一步：
/// Flutter 的 BackdropFilter 没有 colorFilter，历史上只能用一点主题色 tint
/// 近似，结果玻璃底下的颜色一律发灰——"看上去一点也不透"。
/// 用色彩矩阵把饱和度真正提上来，玻璃才会像网页版那样"透且艳"。
///
/// 参数是 4x4、按列主序排的 **16** 项色彩矩阵：0-3 描述 R'，4-7 描述 G'，
/// 8-11 描述 B'，12-15 描述 A'。传 20 项会抛
/// "matrix4 must have 16 entries"（这个 API 没有平移列，平移另走 translate）。
ImageFilter saturate(double s) => ImageFilter.matrix(
  Float64List.fromList(<double>[
    0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, //
    0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, //
    0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, //
    0, 0, 0, 1, //
  ]),
);

/// iOS 26 玻璃风格容器：三层折射模糊 + 半透明材质 + 细描边
/// （style-pack：玻璃只给控制层——顶栏/导航/悬浮控件，内容层用 AppCard）
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = Color(s.accentValue);

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          // ===== iOS 26 液态玻璃：三层折射 =====
          // 每层 = 模糊 + 微小平移（compose）：不同方向/幅度采样背景 →
          // 边缘出现真实的"折射错位"（玻璃厚度感来自位移差，不只是模糊）
          child: Stack(
            children: [
              Positioned.fill(
                child: BackdropFilter(
                  // 一层就够：模糊 + 饱和 + 微小平移合成一个 filter。
                  // 此前叠三层 blur(8/18/34) 是"氛围一开就卡"的同类问题——
                  // 每一层都要重新采样整块背景，层数直接乘进耗时。
                  filter: ImageFilter.compose(
                    outer: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    inner: ImageFilter.compose(
                      outer: saturate(dark ? 1.5 : 1.7),
                      inner: ImageFilter.matrix(
                        (Matrix4.identity()..translateByDouble(0.8, -0.6, 0, 1))
                            .storage,
                      ),
                    ),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              Container(
                padding: padding,
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  // 透镜边缘：网页版每块玻璃都有 `inset 0 1px 0 rgba(255,255,255,.12)`
                  // 这道清脆的顶缘内高光——1px 收边 + 一小段过渡，
                  // 玻璃的"边"才立得住。之前摊成 30% 的白雾，反而把内容冲淡。
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: dark ? 0.26 : 0.52),
                      Colors.white.withValues(alpha: dark ? 0.04 : 0.06),
                      Colors.white.withValues(alpha: 0.0),
                      Colors.black.withValues(alpha: dark ? 0.10 : 0.025),
                    ],
                    stops: const [0, 0.06, 0.34, 1],
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
                            // 用户反馈"太透明模糊"：玻璃底色收实一些，
                            // 透光但能稳稳托住图标文字
                            ? const Color(0xFF131926).withValues(alpha: 0.48)
                            : Colors.white.withValues(alpha: 0.55),
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
    );
  }
}

/// 页面背景：柔和渐变 + 克制的色斑
///
/// 色斑是"玻璃的可折射内容"：玻璃卡要靠背景有东西可模糊才看得出透镜感。
/// 但宁可**少而淡**也不要多而艳——四段 stops 让外圈快速归零，避免"贴了一张图"。
/// 背景彩虹必须是**静态**的（渐入后完全静止）：背景层在玻璃卡
/// BackdropFilter 的采样路径里，任何每帧变化都会逼全屏玻璃每帧重新模糊。
/// 动态流光看 AmbientRainbow。
class GlassWall extends StatelessWidget {
  final Widget child;
  const GlassWall({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    final dark = Theme.of(context).brightness == Brightness.dark;
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
                        const Color(0xFF0B0F1A),
                        Color.alphaBlend(
                          accent.withValues(alpha: 0.16),
                          const Color(0xFF0B0F1A),
                        ),
                        const Color(0xFF0B0F1A),
                      ]
                    : [
                        const Color(0xFFF4F6FB),
                        Color.alphaBlend(
                          accent.withValues(alpha: 0.16),
                          Colors.white,
                        ),
                        const Color(0xFFEDF1F8),
                      ],
              ),
            ),
          ),
        ),
        // 三枚：主题色（右上，紧贴顶栏）、青（左下）、紫（右下）。
        // 粉色那枚已去掉——它不承载任何语义，只增加杂色。
        Positioned(
          top: -110,
          right: -90,
          child: _blob(340, accent.withValues(alpha: dark ? 0.13 : 0.12)),
        ),
        Positioned(
          bottom: -110,
          left: -90,
          child: _blob(
            340,
            const Color(0xFF22D3EE).withValues(alpha: dark ? 0.09 : 0.10),
          ),
        ),
        Positioned(
          bottom: 100,
          right: -140,
          child: _blob(
            300,
            const Color(0xFF8B5CF6).withValues(alpha: dark ? 0.07 : 0.08),
          ),
        ),
        // 压在底部悬浮胶囊下方：胶囊要真的糊到颜色才看得出玻璃感，
        // 否则它背后是一张平色渐变，模糊等于没做。
        Positioned(
          bottom: -60,
          left: -30,
          child: _blob(
            260,
            const Color(0xFF22D3EE).withValues(alpha: dark ? 0.10 : 0.12),
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
              color.withValues(alpha: a * 0.42),
              color.withValues(alpha: a * 0.10),
              color.withValues(alpha: 0),
            ],
            stops: const [0, 0.42, 0.72, 1],
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
///
/// [wall] = false 用于**已经在 HomeShell 的背景墙之内**的页面：
/// 壳层已经铺过一层 GlassWall，页面再铺一层就变成双层渐变 + 6 枚色斑，
/// 既重影又逼玻璃多采样一遍背景。只有 push 出来的独立路由才需要自带背景墙。
class GlassScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final bool wall;

  const GlassScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.wall = true,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        // AppBar 画在背景墙之上（手动补状态栏高度）
        if (appBar != null)
          Padding(
            padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
            child: appBar,
          ),
        Expanded(child: body),
      ],
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: floatingActionButton,
      body: wall ? GlassWall(child: content) : content,
    );
  }
}
