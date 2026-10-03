import 'package:flutter/material.dart';

/// 全项目统一的"从列表选一项"交互（用户约定 2026-09-30）：
/// 一律用底部弹层，禁止再用 DropdownButton / DropdownButtonFormField
/// （其菜单项有 48px 硬性下限，且与整体风格不符）。

/// 表单态选择框：外观同输入框，点击弹 [showSheetPicker]
class SheetPickerField extends StatelessWidget {
  final String label;
  final String placeholder;
  final VoidCallback? onTap;
  final bool enabled;

  const SheetPickerField({
    super.key,
    required this.label,
    required this.placeholder,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        isEmpty: label == placeholder,
        decoration: InputDecoration(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: label == placeholder ? cs.outline : null,
                ),
              ),
            ),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: enabled ? cs.outline : cs.outlineVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// 底部弹层选择器。返回选中项的 value；取消返回 null。
/// [current] 传入当前值时对应项打勾；[title] 显示在弹层顶部。
/// [searchHint] 非空时顶部显示搜索框（长列表用，如全国城市）。
Future<T?> showSheetPicker<T>(
  BuildContext context, {
  String? title,
  required List<(T, String)> options,
  T? current,
  bool addInset = false,
  String? searchHint,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _SheetPickerBody<T>(
      title: title,
      options: options,
      current: current,
      addInset: addInset,
      searchHint: searchHint,
    ),
  );
}

class _SheetPickerBody<T> extends StatefulWidget {
  final String? title;
  final List<(T, String)> options;
  final T? current;
  final bool addInset;
  final String? searchHint;

  const _SheetPickerBody({
    required this.title,
    required this.options,
    required this.current,
    required this.addInset,
    required this.searchHint,
  });

  @override
  State<_SheetPickerBody<T>> createState() => _SheetPickerBodyState<T>();
}

class _SheetPickerBodyState<T> extends State<_SheetPickerBody<T>> {
  String _q = '';

  List<(T, String)> get _filtered {
    final q = _q.trim();
    if (q.isEmpty) return widget.options;
    return widget.options
        .where((o) => o.$2.contains(q) || '${o.$1}'.contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final ctx = context;
    final items = _filtered;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                widget.title!,
                style: Theme.of(ctx).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          if (widget.searchHint != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SizedBox(
                height: 44,
                child: TextField(
                  autofocus: false,
                  onChanged: (v) => setState(() => _q = v),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: widget.searchHint,
                    hintStyle: const TextStyle(fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight:
                  MediaQuery.sizeOf(ctx).height * 0.6 -
                  // 弹窗之上再弹弹层时，扣除键盘高度避免列表被遮
                  (widget.addInset || widget.searchHint != null
                      ? MediaQuery.viewInsetsOf(ctx).bottom
                      : 0),
            ),
            child: items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Text(
                      '没有匹配项',
                      style: Theme.of(ctx).textTheme.bodySmall
                          ?.copyWith(color: Theme.of(ctx).colorScheme.outline),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: items.length,
                    itemBuilder: (ctx, i) {
                      final o = items[i];
                      final selected =
                          widget.current != null && o.$1 == widget.current;
                      return ListTile(
                        dense: true,
                        visualDensity: const VisualDensity(
                          horizontal: 0,
                          vertical: -2,
                        ),
                        title: Text(o.$2, style: const TextStyle(fontSize: 14)),
                        trailing: selected
                            ? Icon(
                                Icons.check_rounded,
                                size: 18,
                                color: Theme.of(ctx).colorScheme.primary,
                              )
                            : null,
                        onTap: () => Navigator.pop(ctx, o.$1),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
