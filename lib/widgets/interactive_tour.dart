import 'package:flutter/material.dart';

/// 交互式教程步骤
class TourStep {
  final GlobalKey? key; // 目标组件（null = 无高亮的说明步）
  final String title;
  final String desc;
  const TourStep(this.key, this.title, this.desc);
}

/// 页面内真实交互教程：蒙层挖洞高亮真实控件 + 上一步/下一步/跳过
class InteractiveTour extends StatefulWidget {
  final List<TourStep> steps;
  const InteractiveTour({super.key, required this.steps});

  static void show(BuildContext context, List<TourStep> steps) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (_, _, _) => InteractiveTour(steps: steps),
      ),
    );
  }

  @override
  State<InteractiveTour> createState() => _InteractiveTourState();
}

class _InteractiveTourState extends State<InteractiveTour> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final step = widget.steps[_i];
          Rect? hole;
          if (step.key?.currentContext != null) {
            final box =
                step.key!.currentContext!.findRenderObject() as RenderBox?;
            if (box != null && box.hasSize) {
              final pos = box.localToGlobal(Offset.zero);
              hole = pos & box.size;
            }
          }
          final anim = hole;
          return Stack(
            children: [
              // 蒙层（洞外遮罩）
              if (anim != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _HolePainter(
                        hole: anim.inflate(8),
                        dim: Colors.black.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                )
              else
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.45),
                  ),
                ),
              // 高亮环
              if (anim != null)
                Positioned(
                  left: anim.left - 8,
                  top: anim.top - 8,
                  width: anim.width + 16,
                  height: anim.height + 16,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cs.primary, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: cs.primary.withValues(alpha: 0.45),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              // 讲解卡片
              Align(
                alignment:
                    anim != null && anim.center.dy < constraints.maxHeight / 2
                    ? Alignment.bottomCenter
                    : Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * 0.72,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cs.primaryContainer),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      // 长说明在矮屏不能顶出屏幕
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_i + 1} / ${widget.steps.length}  ${step.title}',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              step.desc,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(height: 1.5),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('跳过'),
                                ),
                                const Spacer(),
                                if (_i > 0)
                                  TextButton(
                                    onPressed: () => setState(() => _i--),
                                    child: const Text('上一步'),
                                  ),
                                FilledButton(
                                  onPressed: () {
                                    if (_i == widget.steps.length - 1) {
                                      Navigator.of(context).pop();
                                    } else {
                                      setState(() => _i++);
                                    }
                                  },
                                  child: Text(
                                    _i == widget.steps.length - 1
                                        ? '完成'
                                        : '下一步',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 挖洞蒙层
class _HolePainter extends CustomPainter {
  final Rect hole;
  final Color dim;
  _HolePainter({required this.hole, required this.dim});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(hole, const Radius.circular(16));
    final path = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(rrect),
    );
    canvas.drawPath(path, Paint()..color = dim);
  }

  @override
  bool shouldRepaint(covariant _HolePainter old) =>
      old.hole != hole || old.dim != dim;
}
