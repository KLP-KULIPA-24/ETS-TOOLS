import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 托盘右键菜单：Windows 走 C++ 原生玻璃弹窗（windows/runner/tray_menu.cpp），
/// 其余平台退回 tray_manager 的系统菜单。
class TrayMenuService {
  static final I = TrayMenuService._();

  TrayMenuService._();

  static const _channel = MethodChannel('eets/traymenu');

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// 初始化通道回调（main 启动时调用一次）
  static void init({required void Function(int index) onPicked}) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'itemPicked') {
        onPicked((call.arguments as num?)?.toInt() ?? -1);
      }
    });
  }

  /// 在鼠标位置弹出玻璃样式菜单；0=打开主窗口，2=退出（1 是分隔线）。
  /// 返回 false = 自绘菜单没弹出来（引擎侧失败），调用方应回退系统菜单。
  Future<bool> show() async {
    if (!supported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('show', {
        'items': [
          {'label': '打开主窗口', 'separator': false, 'danger': false},
          {'label': '', 'separator': true, 'danger': false},
          {'label': '退出', 'separator': false, 'danger': true},
        ],
      });
      return ok ?? false;
    } on PlatformException catch (e) {
      debugPrint('tray_menu show failed: $e');
      return false;
    } on MissingPluginException {
      debugPrint('tray_menu 未接入，退回系统菜单');
      return false;
    }
  }
}
