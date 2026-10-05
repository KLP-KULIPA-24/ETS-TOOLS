/// 悬浮窗数据桥（内存 + 持久化双通道）
/// Windows 悬浮模式：内存传递；Android 悬浮窗：原生 WindowManager 视图
/// （MainActivity 的 FloatingBall，走 eets/shell 通道）
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/foundation.dart';

import 'achievements.dart';

class FloatingBridge {
  static const _channel = MethodChannel('eets/shell');

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

  /// 显示 Android 悬浮窗（原生 WindowManager 小球）。
  /// 未授权时原生侧直接拉起系统"显示在其他应用上层"设置页，这里返回 false。
  static Future<bool> showAndroidOverlay() async {
    Achievements.unlock('floating');
    try {
      final r = await _channel.invokeMethod<String>('floatingShow', {
        'title': title,
        'answers': answers,
      });
      return r == 'ok';
    } catch (e) {
      assert(() {
        debugPrint('[FloatingBridge] showAndroidOverlay failed: $e');
        return true;
      }());
      return false;
    }
  }

  /// 悬浮窗已显示时，用最新数据刷新内容（详情页打开新作业时调用）
  static Future<void> updateAndroidOverlay() async {
    try {
      await _channel.invokeMethod<String>('floatingUpdate', {
        'title': title,
        'answers': answers,
      });
    } catch (_) {}
  }

  static Future<void> hideAndroidOverlay() async {
    try {
      await _channel.invokeMethod<String>('floatingHide');
    } catch (_) {}
  }

  /// 顶栏按钮的开关切换：显示中→收起；隐藏中→显示。
  /// 返回 true = 切换后是显示态。
  static Future<bool> toggleAndroidOverlay() async {
    try {
      final active =
          await _channel.invokeMethod<bool>('floatingActive') ?? false;
      if (active) {
        await hideAndroidOverlay();
        return false;
      }
      return await showAndroidOverlay();
    } catch (_) {
      return false;
    }
  }
}
