import 'package:flutter/material.dart';

/// 调色窗口：二维饱和度/明度色板 + 色相条 + 当前色预览
class ColorPickerDialog extends StatefulWidget {
  final Color initial;
  const ColorPickerDialog({super.key, required this.initial});

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late HSVColor _hsv;
  // 色板实际宽度按可用空间算；手势换算必须用同一值，否则窄屏取色永远到不了边缘
  double _w = 280.0;
  static const _maxW = 280.0;
  static const _h = 180.0;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
  }

  Color get _current => _hsv.toColor();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // AlertDialog 在 360 屏上 content 可用宽约 232，减掉滚动条/内边距
    final avail = MediaQuery.sizeOf(context).width - 128;
    _w = _maxW.clamp(160.0, avail > 160 ? avail : 160.0);
    return AlertDialog(
      title: const Text('自定义颜色'),
      content: SizedBox(
        width: _w,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // SV 色板
            GestureDetector(
              onPanDown: (d) => _pickSV(d.localPosition),
              onPanUpdate: (d) => _pickSV(d.localPosition),
              onTapDown: (d) => _pickSV(d.localPosition),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: _w,
                  height: _h,
                  child: CustomPaint(
                    painter: _SvPainter(
                      hue: _hsv.hue,
                      sat: _hsv.saturation,
                      val: _hsv.value,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            // 色相条
            GestureDetector(
              onPanDown: (d) => _pickHue(d.localPosition),
              onPanUpdate: (d) => _pickHue(d.localPosition),
              onTapDown: (d) => _pickHue(d.localPosition),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: _w,
                  height: 22,
                  child: CustomPaint(
                    painter: _HuePainter(
                      hue: _hsv.hue,
                      sat: _hsv.saturation,
                      val: _hsv.value,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            // 窄屏放不下「色块 + 色值 + 预设色」一行，预设色换行
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _current,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                ),
                Text(
                  '#${_current.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                for (final c in const [
                  0xFF4F6BFF,
                  0xFF22D3EE,
                  0xFF6750A4,
                  0xFF2E7D32,
                  0xFFEF6C00,
                ])
                  GestureDetector(
                    onTap: () =>
                        setState(() => _hsv = HSVColor.fromColor(Color(c))),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _current),
          child: const Text('使用此颜色'),
        ),
      ],
    );
  }

  void _pickSV(Offset local) {
    final dx = local.dx.clamp(0.0, _w);
    final dy = local.dy.clamp(0.0, _h);
    setState(() {
      _hsv = HSVColor.fromAHSV(1, _hsv.hue, dx / _w, 1 - dy / _h);
    });
  }

  void _pickHue(Offset local) {
    final dx = local.dx.clamp(0.0, _w);
    setState(() {
      _hsv = HSVColor.fromAHSV(1, dx / _w * 360, _hsv.saturation, _hsv.value);
    });
  }
}

/// 饱和度/明度二维色板
class _SvPainter extends CustomPainter {
  final double hue;
  final double sat;
  final double val;
  _SvPainter({required this.hue, required this.sat, required this.val});

  @override
  void paint(Canvas canvas, Size size) {
    final base = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(colors: [Colors.white, base])
            .createShader(Offset.zero & size),
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(Offset.zero & size),
    );
    canvas.drawCircle(
      Offset(sat * size.width, (1 - val) * size.height),
      8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _SvPainter old) =>
      old.hue != hue || old.sat != sat || old.val != val;
}

/// 色相条
class _HuePainter extends CustomPainter {
  final double hue;
  final double sat;
  final double val;
  _HuePainter({required this.hue, required this.sat, required this.val});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          colors: List.generate(
            13,
            (i) => HSVColor.fromAHSV(1, i * 30.0, 1, 1).toColor(),
          ),
        ).createShader(Offset.zero & size),
    );
    canvas.drawCircle(
      Offset(hue / 360 * size.width, size.height / 2),
      8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _HuePainter old) =>
      old.hue != hue || old.sat != sat || old.val != val;
}
