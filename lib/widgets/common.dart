import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../models/ets_models.dart';
import 'style.dart';

/// 题型徽章
class TypeBadge extends StatelessWidget {
  final EtsStructure structure;
  const TypeBadge(this.structure, {super.key});

  Color _colors(EtsStructure s) => switch (s) {
    EtsStructure.word => const Color(0xFF2E7D32),
    EtsStructure.read => const Color(0xFF1565C0),
    EtsStructure.threeQ5A => const Color(0xFF6A1B9A),
    EtsStructure.picture => const Color(0xFFEF6C00),
    EtsStructure.repeatDialogue => const Color(0xFF00838F),
    EtsStructure.unknown => const Color(0xFF616161),
  };

  @override
  Widget build(BuildContext context) {
    final c = _colors(structure);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Text(
        structure.label,
        style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// 标题来源徽章
class TitleSourceBadge extends StatelessWidget {
  final TitleSource source;
  const TitleSourceBadge(this.source, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = switch (source) {
      TitleSource.template => Colors.green,
      TitleSource.adaptive => Colors.blue,
      TitleSource.ai => Colors.deepPurple,
      TitleSource.fallback => Colors.grey,
    };
    return Tooltip(
      message: '标题来源：${source.label}',
      child: Icon(
        switch (source) {
          TitleSource.template => Icons.fact_check_outlined,
          TitleSource.adaptive => Icons.auto_awesome_motion_outlined,
          TitleSource.ai => Icons.auto_awesome,
          TitleSource.fallback => Icons.label_outline,
        },
        size: 14,
        color: color,
      ),
    );
  }
}

/// 通用区块卡片
class SectionCard extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Widget? trailing;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  const SectionCard({
    super.key,
    required this.title,
    this.icon,
    this.trailing,
    required this.children,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppCard(
      radius: 16,
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: cs.primary),
                  const SizedBox(width: 6),
                ],
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                ?trailing,
              ],
            ),
          ),
          Padding(
            padding: padding,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

/// 背题模式开关（模糊答案，点击显示）
class BlurReveal extends StatefulWidget {
  final Widget child;
  final String hint;
  const BlurReveal({super.key, required this.child, this.hint = '点击显示答案'});

  @override
  State<BlurReveal> createState() => _BlurRevealState();
}

class _BlurRevealState extends State<BlurReveal> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _revealed = !_revealed),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        child: Stack(
          alignment: Alignment.center,
          children: [
            ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: _revealed ? 0 : 8,
                sigmaY: _revealed ? 0 : 8,
              ),
              child: Opacity(
                opacity: _revealed ? 1 : 0.75,
                child: widget.child,
              ),
            ),
            if (!_revealed)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer
                      .withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.visibility_off_rounded,
                      size: 14,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.hint,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
