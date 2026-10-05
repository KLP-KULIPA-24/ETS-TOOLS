/// 悬浮窗数据桥（内存 + 持久化双通道）
/// Windows 悬浮模式：内存传递；Android 悬浮窗：SharedPreferences 跨 engine
library;

import 'dart:convert';

import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/foundation.dart';

import 'achievements.dart';

class FloatingBridge {
  static final ValueNotifier<bool> inFloating = ValueNotifier(false);
  static String title = '';
  static String answers = '';
  static String stid = '';

  /// 主界面 → 悬浮窗（Windows 内存 / Android 持久化）
  static Future<void> set({
    required String title,
    required String answers,
    String stid = '',
  }) async {
    FloatingBridge.title = title;
    FloatingBridge.answers = answers;
    FloatingBridge.stid = stid;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        'overlay_payload',
        jsonEncode({'title': title, 'answers': answers, 'stid': stid}),
      );
    } catch (_) {}
  }

  /// 悬浮窗侧读取（Android 独立 engine）
  static Future<({String title, String answers, String stid})> load() async {
    if (title.isNotEmpty) return (title: title, answers: answers, stid: stid);
    try {
      final sp = await SharedPreferences.getInstance();
      final s = sp.getString('overlay_payload');
      if (s == null) return (title: '', answers: '', stid: '');
      final j = jsonDecode(s) as Map<String, dynamic>;
      return (
        title: '${j['title'] ?? ''}',
        answers: '${j['answers'] ?? ''}',
        stid: '${j['stid'] ?? ''}',
      );
    } catch (_) {
      return (title: '', answers: '', stid: '');
    }
  }

  /// 请求 Android 悬浮窗权限并显示（折叠圆形）
  /// 某些 ROM（含模拟器）在已授权时 isPermissionGranted 仍误报 false——
  /// 因此先探测/直启悬浮窗，失败才走系统授权页，避免"已允许却反复跳设置"。
  static Future<bool> showAndroidOverlay() async {
    Achievements.unlock('floating');
    try {
      if (await FlutterOverlayWindow.isActive()) return true;
      try {
        await FlutterOverlayWindow.showOverlay(
          height: 148,
          width: 148,
          alignment: OverlayAlignment.center,
          flag: OverlayFlag.focusPointer,
          enableDrag: true,
          positionGravity: PositionGravity.none,
        );
        return true;
      } catch (_) {
        // 直启失败：多为未授权，走一次系统授权流程
        final granted = await FlutterOverlayWindow.isPermissionGranted();
        if (granted != true) {
          final ok = await FlutterOverlayWindow.requestPermission();
          if (ok != true) return false;
        }
        await FlutterOverlayWindow.showOverlay(
          height: 148,
          width: 148,
          alignment: OverlayAlignment.center,
          flag: OverlayFlag.focusPointer,
          enableDrag: true,
          positionGravity: PositionGravity.none,
        );
        return true;
      }
    } catch (e) {
      assert(() {
        debugPrint('[FloatingBridge] showAndroidOverlay failed: $e');
        return true;
      }());
      return false;
    }
  }

  static Future<void> hideAndroidOverlay() async {
    try {
      await FlutterOverlayWindow.closeOverlay();
    } catch (_) {}
  }

  /// 顶栏按钮的开关切换：显示中→收起；隐藏中→显示。
  /// 返回 true = 切换后是显示态。
  static Future<bool> toggleAndroidOverlay() async {
    try {
      if (await FlutterOverlayWindow.isActive()) {
        await hideAndroidOverlay();
        return false;
      }
      return await showAndroidOverlay();
    } catch (_) {
      return false;
    }
  }
}
