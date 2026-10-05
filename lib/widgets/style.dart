/// 样式基建（对齐 docs/style-pack/tokens.json）：
/// - AppRadius / AppSpace / AppShadow / AppText：规范值常量层
/// - AppCard：内容层实底卡（surface + border + radius16 + shadow.card）
/// - GlassTopBar：控制层玻璃顶栏（导航/工具栏）
/// - PressableScale：pointer-down 按压缩放反馈（0.97 / 120ms）
/// - Qbounce：三段式 Q 弹动画（0.92 → 1.05 → 1，280ms）
library;

import 'package:flutter/material.dart';

import 'glass.dart';

/// token 颜色（深色为规范值；浅色为派生）
class StyleTokens {
  static const darkBg = Color(0xFF0F1115);
  static const darkSurface = Color(0xFF171A21);
  static const darkBorder = Color(0xFF2A2F3A);
  static const darkText = Color(0xFFE6E8EC);
  static const darkTextMuted = Color(0xFF9AA1AC);
  static const glassTintDark = Color(0x24FFFFFF); // rgba(255,255,255,0.14)
  // 浅色玻璃 tint 对齐网页版 docs/index.html 的 --glass-tint: rgba(255,255,255,.55)。
  // 之前压到 0.24 是"没有 saturate 时靠降透明度掩盖发灰"的补偿，
  // saturate 补上后就不再需要压这么低。
  // 浅色玻璃 tint：压得越低越透，玻璃感越强（背景要真有颜色才看得出模糊）。
  // 网页版是 .55，但网页背景有大幅色块；App 背景更安静，这里取 .34。
  static const glassTintLight = Color(0x57FFFFFF); // 白 0.34
  static const defaultAccent = Color(0xFF4F7CFF); // tokens.json primary

  // 语义色：来源是 common.dart 里那套已验证的题型徽章色 —— 全库唯一
  // 真正醒目、且用「低透明底 + 纯色字」处理得成熟的范式。提升为全局色板。
  static const success = Color(0xFF2E7D32);
  static const info = Color(0xFF1565C0);
  static const purple = Color(0xFF6A1B9A);
  static const warning = Color(0xFFEF6C00);
  static const teal = Color(0xFF00838F);
  static const danger = Color(0xFFB3261E);

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

  /// 全应用统一的「实色落点」取色。
  ///
  /// 必须取 `colorScheme.primary` 而不是设置页存的原始 accent：
  /// ColorScheme.fromSeed 会把种子色映射到 M3 的色调梯度，得到的 primary
  /// 明显更深；此前导航胶囊用原始色、chip 用派生色，同一套语言出现两种蓝。
  static Color accentOf(BuildContext context) =>
      Theme.of(context).colorScheme.primary;
}

/// 圆角（tokens.json radius）
class AppRadius {
  static const card = 16.0;
  static const sheet = 10.0;
  static const input = 999.0; // 控制族统一胶囊（按钮/chip/输入框）
  static const control = 999.0;

  static const cardR = BorderRadius.all(Radius.circular(card));
  static const sheetR = BorderRadius.all(Radius.circular(sheet));
  static const capsule = BorderRadius.all(Radius.circular(control));
}

/// 间距（tokens.json space）
class AppSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const huge = 48.0;
}

/// 阴影（tokens.json shadow）
///
/// **整表保留但一律为空**：原先给卡片挂了 `blur 24 / offset(0,8)` 的柔影，
/// 实际渲染时阴影会向上漫到卡片顶边，在浅底上糊出一条灰带——正是用户嫌恶的
/// "阴影效果"。层次改由「158° 斜向渐变 + 发丝边 + 顶缘内高光」承担，
/// 和网页版 `.card` 的做法一致（它的 inset 高光也不带外部投影）。
/// 这里保留空实现是为了让调用点不必再改，日后若要恢复投影只改这一处。
class AppShadow {
  static List<BoxShadow> card(Brightness b) => const [];
  static List<BoxShadow> sm(Brightness b) => const [];
  static const glass = <BoxShadow>[];
}

/// 字号与字重（tokens.json font）
class AppText {
  static const xs = 12.0;
  static const sm = 13.0;
  static const md = 14.0;
  static const lg = 18.0;
  static const xl = 24.0;

  static const wNormal = FontWeight.w400;
  static const wMedium = FontWeight.w500;
  static const wBold = FontWeight.w600;
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
    // 内容层**不做玻璃**（style-pack：玻璃只给导航/控制层）：实底卡片 + 细边。
    // 用户红线：①不要透明模糊（BackdropFilter 已去掉）②顶端前缘不要任何
    // 颜色/阴影——此前的"顶缘内高光"渐变在实机上渲染成一条压暗的灰带
    // （用户连报三次"怎么还有阴影"），已整块删除。
    Widget body = Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: color == null
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? [
                        Color.alphaBlend(
                          Colors.white.withValues(alpha: 0.085),
                          const Color(0xFF222836),
                        ),
                        Color.alphaBlend(
                          Colors.white.withValues(alpha: 0.02),
                          const Color(0xFF1B202C),
                        ),
                      ]
                    : [Colors.white, Colors.white.withValues(alpha: 0.96)],
                stops: const [0, 0.62],
              )
            : null,
        color: color,
        borderRadius: radiusR,
        border: Border.all(
          color:
              border?.top.color ??
              (dark
                  ? StyleTokens.borderOf(b).withValues(alpha: 0.9)
                  : const Color(0x1F111628)),
        ), // 浅色：灰蓝细边（白边在白底上等于没有）
        boxShadow: AppShadow.card(b),
      ),
      child: child,
    );
    if (margin != null) body = Padding(padding: margin!, child: body);
    if (onTap == null) return body;
    return PressableScale(
      child: InkWell(borderRadius: radiusR, onTap: onTap, child: body),
    );
  }
}

/// 胶囊标签：底部导航项 / 筛选 chip / 排序 chip 全用这一个，
/// 保证「选中=实色主题色 + 白图标白字」这套语言在上下两处完全一致。
/// [filled] 让未选中态带一层极淡底（用于需要读出「可点」的筛选 chip），
/// 底部导航则用默认的透明底。
class PillTab extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;
  final bool filled;
  final double height;

  /// 自定义前缀（转圈等），给定时取代 [icon]
  final Widget? leading;

  /// 横排（筛选 chip）/ 竖排（底部导航项）。选中态语言两种方向完全一致。
  final Axis axis;
  final double iconSize;

  const PillTab({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
    this.filled = false,
    this.height = 40,
    this.leading,
    this.axis = Axis.horizontal,
    this.iconSize = 16,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final b = Theme.of(context).brightness;
    // 前景用 onPrimary 而非硬编码白：浅色主题 primary 深 → onPrimary 是白；
    // 深色主题 primary 变浅 → onPrimary 随之变深。写死白色在深色下会糊成一片。
    final fg = selected ? cs.onPrimary : cs.onSurfaceVariant;
    final gap = axis == Axis.vertical
        ? const SizedBox(height: AppSpace.xs)
        : const SizedBox(width: AppSpace.xs);
    Widget inner = Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
      decoration: BoxDecoration(
        color: selected
            ? StyleTokens.accentOf(context)
            : (filled
                  ? StyleTokens.textOf(b).withValues(alpha: 0.06)
                  : Colors.transparent),
        borderRadius: AppRadius.capsule,
      ),
      child: Flex(
        direction: axis,
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (leading != null) ...[
            SizedBox(
              width: 16,
              height: 16,
              child: Center(
                child: IconTheme(
                  data: IconThemeData(color: fg, size: 16),
                  child: leading!,
                ),
              ),
            ),
            gap,
          ] else if (icon != null) ...[
            Icon(icon, size: iconSize, color: fg),
            gap,
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppText.sm,
                fontWeight: selected ? AppText.wBold : AppText.wMedium,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
    inner = Qbounce(trigger: selected ? 1 : -1, child: inner);
    if (onTap == null) return inner;
    return PressableScale(onTap: onTap, child: inner);
  }
}

/// 控制层玻璃顶栏（工具栏/导航栏专用；禁止用于内容层）
///
/// 全应用统一走这一个：壳顶栏、详情页、AI 页都用它，杜绝再出现
/// 「一个实一个透」的两套顶栏语言。底缘发丝线在浅色下用深灰蓝，
/// 不用白——白线压在浅背景上等于隐形。
class GlassTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;

  /// 品牌图标。**不能**塞给 AppBar 的 leading 槽——那个槽宽度固定，
  /// 会把图标横向撑开再被 BoxFit.cover 压扁。放进标题行里才拿得到正方约束。
  final Widget? logo;

  const GlassTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.leading,
    this.logo,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (subtitle == null ? 0 : 14));

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final dark = b == Brightness.dark;
    return GlassContainer(
      radius: 0,
      color: dark
          ? const Color(0xFF141A26).withValues(alpha: 0.62)
          : Colors.white.withValues(alpha: 0.66),
      border: Border(
        bottom: BorderSide(
          color: dark
              ? Colors.white.withValues(alpha: 0.10)
              : StyleTokens.borderOf(b).withValues(alpha: 0.9),
        ),
      ),
      child: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        leading: leading,
        title: Row(
          children: [
            if (logo != null) ...[logo!, const SizedBox(width: AppSpace.md)],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppText.lg,
                      fontWeight: AppText.wBold,
                      letterSpacing: -0.2,
                      color: StyleTokens.textOf(b),
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppText.xs,
                        fontWeight: AppText.wMedium,
                        color: StyleTokens.accentOf(context),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: actions,
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
