/// 悬浮窗调整面板：大小 / 不透明度 / 电脑端置顶 + 快捷键开关。
/// 底部导航的「悬浮窗」按钮与设置页卡片共用这一份，避免两套 UI 走样。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../services/floating_bridge.dart';
import '../services/hotkey_channel.dart';
import '../services/settings_service.dart';
import 'style.dart';

/// 弹出悬浮窗设置面板
Future<void> showFloatingSettingsSheet(BuildContext context) {
  final s = context.read<SettingsService>();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Platform.isWindows
                          ? Icons.desktop_windows_outlined
                          : Icons.picture_in_picture_alt_rounded,
                      size: 18,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      // 电脑端没有悬浮球，只有窗口置顶/快捷键——标题跟着平台走，
                      // 免得在电脑上看到"悬浮窗"字样（用户：电脑不要出现悬浮窗的功能设置）
                      Platform.isWindows ? '窗口' : '悬浮窗',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: AppText.wBold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // 悬浮球控制（大小/不透明度/配色/开合）只在安卓出：
                // 电脑端的悬浮窗功能早已下架，摆出来就是一堆按不动的死控件
                if (!Platform.isWindows) ...[
                // 大小：悬浮球直径（与不透明度一样是滑杆）
                Row(
                  children: [
                    Text('悬浮球大小', style: TextStyle(fontSize: 12, color: cs.outline)),
                    const Spacer(),
                    Text(
                      '${s.floatingSize} px',
                      style: TextStyle(fontSize: 12, color: cs.outline),
                    ),
                  ],
                ),
                Slider(
                  value: s.floatingSize.toDouble().clamp(40, 200),
                  min: 40,
                  max: 200,
                  divisions: 16, // 每 10px 一档
                  label: '${s.floatingSize} px',
                  onChanged: (v) => s.setFloatingSize(v.round()),
                ),
                const SizedBox(height: 4),
                // 不透明度
                Row(
                  children: [
                    Text('不透明度', style: TextStyle(fontSize: 12, color: cs.outline)),
                    const Spacer(),
                    Text(
                      '${(s.floatingOpacity * 100).round()}%',
                      style: TextStyle(fontSize: 12, color: cs.outline),
                    ),
                  ],
                ),
                Slider(
                  value: s.floatingOpacity,
                  min: 0.4,
                  max: 1.0,
                  divisions: 12,
                  label: '${(s.floatingOpacity * 100).round()}%',
                  onChanged: (v) => s.setFloatingOpacity(v),
                  onChangeEnd: (_) => FloatingBridge.applyAndroidOverlay(
                    sizeDp: s.floatingSize,
                    opacity: s.floatingOpacity,
                  ),
                ),
                const SizedBox(height: 4),
                // 背景配色：跟随主题 / 浅色 / 深色
                Text(
                  '悬浮窗配色',
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'follow', label: Text('跟随')),
                    ButtonSegment(value: 'light', label: Text('浅色')),
                    ButtonSegment(value: 'dark', label: Text('深色')),
                  ],
                  selected: {s.floatingTheme},
                  onSelectionChanged: (v) => s.setFloatingTheme(v.first),
                ),
                // 立即开合也是安卓专属：控制的是悬浮球
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final (ok, _) = await FloatingBridge.toggleAndroidOverlay();
                    if (!context.mounted) return;
                    if (!ok) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            '未获得悬浮窗权限：请在系统设置里允许'
                            '「显示在其他应用上层」',
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('显示 / 隐藏悬浮窗'),
                ),
                ], // end of !Platform.isWindows（悬浮球专属）
                const SizedBox(height: 4),
                // 电脑端：窗口置顶 + 快捷键
                if (Platform.isWindows) ...[
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('窗口置顶', style: TextStyle(fontSize: 14)),
                    subtitle: const Text(
                      '窗口始终显示在最前',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: s.alwaysOnTop,
                    onChanged: (v) async {
                      s.setAlwaysOnTop(v);
                      await windowManager.setAlwaysOnTop(v);
                    },
                  ),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('快捷键显示/隐藏', style: TextStyle(fontSize: 14)),
                    subtitle: const Text(
                      'Ctrl+Alt+E 一键呼出或收起窗口',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: s.hotkeyToggle,
                    onChanged: (v) async {
                      s.setHotkeyToggle(v);
                      await HotkeyChannel.setEnabled(v);
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}
