import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 倍速选择面板：预设档 + 滑杆拖动 + 手动输入任意数值（音频/视频共用）
///
/// 之前是"点一下循环下一档"或固定几档下拉，用户要"能拖、能输"。
/// 范围 0.25x–3.0x，步进 0.05。
Future<double?> showSpeedSheet(
  BuildContext context, {
  required double current,
}) {
  final cs = Theme.of(context).colorScheme;
  var value = current.clamp(0.25, 3.0);
  final ctrl = TextEditingController(text: _trim(current));
  return showModalBottomSheet<double>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            4,
            20,
            16 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.speed_rounded, size: 18, color: cs.primary),
                  const SizedBox(width: 6),
                  const Text(
                    '播放倍速',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Text(
                    '${_trim(value)}x',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // 滑杆：随时可拖
              SliderTheme(
                data: SliderTheme.of(ctx).copyWith(
                  trackHeight: 6,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 9,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 18,
                  ),
                ),
                child: Slider(
                  value: value,
                  min: 0.25,
                  max: 3.0,
                  divisions: 55, // 0.05 步进
                  label: '${_trim(value)}x',
                  onChanged: (v) {
                    ctrl.text = _trim(v);
                    setSheet(() => value = v);
                  },
                  onChangeEnd: (v) => Navigator.of(ctx).pop(v),
                ),
              ),
              // 常用档位
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in const [
                    0.25,
                    0.5,
                    0.75,
                    1.0,
                    1.25,
                    1.5,
                    2.0,
                    3.0,
                  ])
                    ChoiceChip(
                      label: Text('${_trim(r)}x'),
                      selected: (value - r).abs() < 0.001,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => Navigator.of(ctx).pop(r),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // 手动输入任意数值
              TextField(
                controller: ctrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: const InputDecoration(
                  labelText: '自定义倍速',
                  hintText: '0.25 – 3.0，支持两位小数',
                  isDense: true,
                ),
                onSubmitted: (v) => _applyText(ctx, ctrl.text, value),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => _applyText(ctx, ctrl.text, value),
                    child: const Text('确定'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void _applyText(BuildContext ctx, String text, double fallback) {
  final v = double.tryParse(text.trim());
  Navigator.of(ctx).pop(v == null ? fallback : v.clamp(0.25, 3.0));
}

String _trim(double v) {
  final s = v.toStringAsFixed(2);
  return s.endsWith('0') && !s.endsWith('.00')
      ? s.substring(0, s.length - 1)
      : (s.endsWith('.00') ? s.substring(0, s.length - 3) : s);
}
