import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 修改模块专用日志：写到 <应用支持目录>/capture/logs/engine-yyyyMMdd.log
/// （Windows 上即 %APPDATA%\com.eets\e_ets_helper\capture\logs）
///
/// 引擎每个关键事件都落盘（含 body 诊断摘要），UI 事件行只留结论——
/// 之前 12 行额度会被隧道噪音挤掉，导致关键行看不见。
class CaptureLog {
  CaptureLog._();

  static final I = CaptureLog._();

  File? _file;
  IOSink? _sink;
  final _pending = <String>[];
  Directory? _dir;

  /// 日志目录真实路径（未初始化时给 Windows 常见位置兜底）
  static String get hintPath {
    if (I._dir != null) return I._dir!.path;
    final v = Platform.environment['APPDATA'];
    if (Platform.isWindows && v != null) {
      return p.join(v, 'com.eets', 'e_ets_helper', 'capture', 'logs');
    }
    return '（启动后生成于应用支持目录/capture/logs）';
  }

  Future<void> init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final logDir = Directory(p.join(dir.path, 'capture', 'logs'));
      _dir = logDir;
      await logDir.create(recursive: true);
      final now = DateTime.now();
      final name = 'engine-${now.year}${_two(now.month)}${_two(now.day)}.log';
      _file = File(p.join(logDir.path, name));
      if (await _file!.length() > 4 * 1024 * 1024) {
        await _file!.rename(p.join(logDir.path, 'engine-prev.log'));
        _file = File(p.join(logDir.path, name));
      }
      // 异步顺序写，不阻塞引擎事件循环
      _sink = _file!.openWrite(mode: FileMode.append);
      for (final line in _pending) {
        _sink!.writeln(line);
      }
      _pending.clear();
      await w('=== 引擎启动 ${now.toIso8601String()} ===');
    } catch (e) {
      debugPrint('CaptureLog init: $e');
    }
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// 写一行日志（[ts] 可选时间戳前缀，默认带）
  Future<void> w(String msg, {bool ts = true}) async {
    final now = DateTime.now();
    final line = ts
        ? '[${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}] $msg'
        : msg;
    final sink = _sink;
    if (sink == null) {
      _pending.add(line);
      if (_pending.length > 2000) _pending.removeAt(0);
      return;
    }
    sink.writeln(line);
    // 顺带输出到控制台，flutter run 时可见
    debugPrint('[capture] $msg');
  }

  /// body 诊断摘要：长度 + 解码后可见字段名（不落 token 等敏感值）
  Future<void> dumpSync(String where, Uint8List body) async {
    try {
      final text = utf8.decode(body, allowMalformed: true);
      final env = jsonDecode(text);
      if (env is! Map || env['body'] is! String) {
        await w(
          '  [$where] 非信封格式: ${text.substring(0, text.length < 120 ? text.length : 120)}',
        );
        return;
      }
      final raw = (env['body'] as String).replaceAll(RegExp(r'\s'), '');
      final inner = jsonDecode(utf8.decode(base64.decode(raw)));
      if (inner is! List || inner.isEmpty) {
        await w('  [$where] body 非数组: ${inner.runtimeType}');
        return;
      }
      for (var i = 0; i < inner.length && i < 3; i++) {
        final item = inner[i];
        if (item is! Map) continue;
        final params = item['params'];
        final keys = params is Map ? params.keys.join(',') : 'no-params';
        var sd = '';
        if (params is Map && params['score_detail'] != null) {
          try {
            final d = jsonDecode('${params['score_detail']}');
            if (d is Map) {
              sd =
                  ' | detail{score=${d['score']} total=${d['total_score']} '
                  'cat=${d['category']}}';
            }
          } catch (_) {
            sd =
                ' | detail<非JSON:${'${params['score_detail']}'.substring(0, 60)}>';
          }
        }
        await w('  [$where] r="${item['r']}" keys=[$keys]$sd');
      }
    } catch (e) {
      await w('  [$where] 解析失败: $e');
    }
  }
}
