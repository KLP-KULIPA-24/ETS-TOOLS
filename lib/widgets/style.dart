/// 样式基建（对齐 docs/style-pack/tokens.json）：
/// - AppCard：内容层实底卡（surface + border + radius16 + shadow.sm）
/// - LiquidGlass：控制层玻璃（导航/工具栏/浮动控件），胶囊或指定圆角
/// - PressableScale：pointer-down 按压缩放反馈（0.97 / 120ms）
/// - Qbounce：三段式 Q 弹动画（0.92 → 1.05 → 1，280ms）
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings_service.dart';

/// token 颜色（深色为规范值；浅色为派生）
class StyleTokens {
  static const darkBg = Color(0xFF0F1115);
  static const darkSurface = Color(0xFF171A21);
  static const darkBorder = Color(0xFF2A2F3A);
  static const darkText = Color(0xFFE6E8EC);
  static const darkTextMuted = Color(0xFF9AA1AC);
  static const glassTintDark = Color(0x24FFFFFF); // rgba(255,255,255,0.14)
  static const glassTintLight = Color(0x3DFFFFFF); // 白 0.24（iOS 26 通透玻璃）

  static Color bgOf(Brightness b) =>
      b == Brightness.dark ? darkBg : const Color(0xFFF6F7F9);
  static Color surfaceOf(Brightness b) =>
      b == Brightness.dark ? darkSurface : Colors.white;
  static Color borderOf(Brightness b) =>
      b == Brightness.dark ? darkBorder : const Color(0xFFE3E6EC);
  static Color textOf(Brightness b) =>
      b == Brightness.dark ? darkText : const Color(0xFF111318);
  // 浅色主题次要文字加深：0x6B7280 在白卡上太灰（"灰蒙蒙"主因之一）
  static Color textMutedOf(Brightness b) =>
      b == Brightness.dark ? darkTextMuted : const Color(0xFF4B5260);
}

/// 内容层实底卡（列表、卡片、设置块等——禁止玻璃）
class AppCard extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final Border? border;
  final VoidCallback? onTap;
  final Color? onTapColor;

  const AppCard({
    super.key,
    required this.child,
    this.radius = 16,
    this.padding,
    this.margin,
    this.color,
    this.border,
    this.onTap,
    this.onTapColor,
  });

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final dark = b == Brightness.dark;
    final radiusR = BorderRadius.circular(radius);
    final body = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        // 内容层也走玻璃：半透（背景可透），靠描边+阴影立层次
        color:
            color ??
            (dark
                ? StyleTokens.surfaceOf(b).withValues(alpha: 0.42)
                : Colors.white.withValues(alpha: 0.55)),
        borderRadius: radiusR,
        border: Border.all(
          color:
              border?.top.color ??
              (dark
                  ? StyleTokens.borderOf(b).withValues(alpha: 0.85)
                  : const Color(0x14111628)),
        ), // 浅色：灰蓝细边（白边在白底上等于没有）
        boxShadow: [
          // 柔和纵深：贴近网页卡片的 shadow.sm→md 之间的观感
          BoxShadow(
            color: Color.alphaBlend(
              Colors.black.withValues(alpha: dark ? 0.34 : 0.07),
              Colors.transparent,
            ),
            blurRadius: dark ? 14 : 18,
            offset: Offset(0, dark ? 5 : 6),
            spreadRadius: -4,
          ),
        ],
      ),
      // 顶缘内高光（液态玻璃的“边”）：**必须极淡** —— foregroundDecoration 盖在内容之上，
      // 浅色用白色高 alpha 会把标题/图标/说明文字一起冲淡（“灰蒙蒙”的真凶）
      foregroundDecoration: BoxDecoration(
        borderRadius: radiusR,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [Colors.white.withValues(alpha: 0.05), Colors.transparent]
              : [Colors.white.withValues(alpha: 0.18), Colors.transparent],
          stops: const [0, 0.42],
        ),
      ),
      child: child,
    );
    if (onTap == null) return body;
    return PressableScale(
      child: InkWell(borderRadius: radiusR, onTap: onTap, child: body),
    );
  }
}

/// 控制层 Liquid Glass（导航/工具栏/浮动控件专用；禁止用于内容层）
class LiquidGlass extends StatelessWidget {
  final Widget child;
  final BorderRadius radius;
  final EdgeInsetsGeometry? padding;
  final bool clear; // clear 变体：富媒体上方播放控件（更淡 + 调暗层）

  const LiquidGlass({
    super.key,
    required this.child,
    this.radius = const BorderRadius.all(Radius.circular(999)),
    this.padding,
    this.clear = false,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = Color(context.watch<SettingsService>().accentValue);
    final base = clear
        ? (dark
              ? Colors.black.withValues(alpha: 0.45)
              : Colors.black.withValues(alpha: 0.25))
        : (dark ? StyleTokens.glassTintDark : StyleTokens.glassTintLight);
    // 主题色微量透进玻璃：材质"有色"而不是死白（iOS 26 的材质反应感）
    // tint 压到 0.06/0.08：此前 0.15/0.20 叠上背景色斑后，
    // 控制层（尤其 AI 对话顶栏）读作一块实色紫带，很突兀
    final tint = Color.alphaBlend(
      accent.withValues(alpha: dark ? 0.08 : 0.06),
      base,
    );
    return ClipRRect(
      borderRadius: radius,
      // ===== iOS 26 液态玻璃控制层：三层深度折射（6/18/38）=====
      // 近层保留高频细节、中层过渡、远层大面积虚化——透镜厚度感
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 38, sigmaY: 38),
              child: const SizedBox.expand(),
            ),
          ),
          Container(
            padding: padding,
            foregroundDecoration: clear
                ? BoxDecoration(
                    borderRadius: radius,
                    color: Colors.black.withValues(alpha: 0.10),
                  )
                : BoxDecoration(
                    // 顶缘高光带 + 底缘微暗：控制层更薄的“玻璃边”
                    borderRadius: radius,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: dark ? 0.16 : 0.34),
                        Colors.white.withValues(alpha: 0.0),
                        Colors.black.withValues(alpha: dark ? 0.08 : 0.02),
                      ],
                      stops: const [0, 0.45, 1],
                    ),
                  ),
            decoration: BoxDecoration(
              color: tint,
              borderRadius: radius,
              border: Border.all(
                width: 1.1,
                color: dark
                    ? Colors.white.withValues(alpha: 0.26)
                    : Colors.white.withValues(alpha: 0.92),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ), // shadow.glass
              ],
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// 按压反馈：pointer-down 即缩放 0.97，120ms ease-out
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressScale;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressScale = 0.97,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTap: () {
        setState(() => _down = false);
        widget.onTap?.call();
      },
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? widget.pressScale : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Q 弹三段式动画（选中态触发：1 → 0.92 → 1.05 → 1，280ms）
class Qbounce extends StatefulWidget {
  final Widget child;
  final int trigger; // 变化时触发一次 Q 弹
  const Qbounce({super.key, required this.child, required this.trigger});

  @override
  State<Qbounce> createState() => _QbounceState();
}

class _QbounceState extends State<Qbounce> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );

  @override
  void didUpdateWidget(Qbounce old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        // 三段式：0→0.6 缩到 0.92；0.6→0.85 弹到 1.05；0.85→1 回 1
        double scale;
        if (t < 0.6) {
          scale = 1 - (1 - 0.92) * (t / 0.6);
        } else if (t < 0.85) {
          scale = 0.92 + (1.05 - 0.92) * ((t - 0.6) / 0.25);
        } else {
          scale = 1.05 - 0.05 * ((t - 0.85) / 0.15);
        }
        return Transform.scale(scale: scale, child: child);
      },
      child: widget.child,
    );
  }
}
