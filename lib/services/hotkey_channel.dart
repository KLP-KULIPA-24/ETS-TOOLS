/// 电脑端全局热键通道（Ctrl+Alt+E 显示/隐藏窗口）。
///
/// 原生侧在 windows/runner/flutter_window.cpp：RegisterHotKey + WM_HOTKEY
/// 转成 `hotkeyPressed` 方法回调。这里负责注册开关与窗口显隐。
/// window_manager 0.4.x 自身没有全局热键 API，故走自定义通道。
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

class HotkeyChannel {
  HotkeyChannel._();
  static final HotkeyChannel I = HotkeyChannel._();

  static const _ch = MethodChannel('eets/hotkey');

  /// 启动时调用一次：接上原生回调 + 按设置注册热键
  static Future<void> init({required bool enabled}) async {
    if (!Platform.isWindows) return;
    _ch.setMethodCallHandler((call) async {
      if (call.method != 'hotkeyPressed') return;
      // 隐藏中→显示并聚焦；显示中→收起
      if (await windowManager.isVisible()) {
        await windowManager.hide();
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
    });
    await setEnabled(enabled);
  }

  static Future<void> setEnabled(bool enabled) async {
    if (!Platform.isWindows) return;
    try {
      await _ch.invokeMethod('setHotkey', {'enabled': enabled});
    } catch (_) {}
  }
}
