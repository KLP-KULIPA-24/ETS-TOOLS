import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'ets_data_service.dart';
import 'settings_service.dart';

/// Root / Shizuku 提权通道
class ShellService {
  static const _channel = MethodChannel('eets/shell');

  /// E听说 在 Android 上的真实数据源
  static const etsSourceBase =
      '/storage/emulated/0/Android/data/com.ets100.secondary/files/Download/ETS_secondary';

  static ({bool root, bool shizuku, bool shizukuInstalled})? lastProbe;

  /// 探测可用提权通道
  static Future<({bool root, bool shizuku, bool shizukuInstalled})?>
  probe() async {
    if (!Platform.isAndroid) return null;
    try {
      final r = await _channel.invokeMethod<Map>('probe');
      final root = (r?['root'] == true) && SettingsService.I.useRoot;
      final shizuku = (r?['shizuku'] == true) && SettingsService.I.useShizuku;
      final installed =
          (r?['shizukuInstalled'] == true) && SettingsService.I.useShizuku;
      lastProbe = (root: root, shizuku: shizuku, shizukuInstalled: installed);
      return lastProbe;
    } catch (_) {
      lastProbe = (root: false, shizuku: false, shizukuInstalled: false);
      return lastProbe;
    }
  }

  /// 请求 Shizuku 授权
  static Future<String> requestShizuku() async {
    try {
      return '${await _channel.invokeMethod<String>('requestShizuku')}';
    } catch (_) {
      return 'unavailable';
    }
  }

  /// 通过提权通道执行 shell 命令
  static Future<({int exit, String out, String err, String via})?> exec(
    String cmd,
  ) async {
    try {
      final r = await _channel
          .invokeMethod<Map>('exec', {'cmd': cmd})
          .timeout(const Duration(minutes: 3));
      return (
        exit: (r?['exit'] as num?)?.toInt() ?? -1,
        out: '${r?['out'] ?? ''}',
        err: '${r?['err'] ?? ''}',
        via: '${r?['via'] ?? ''}',
      );
    } catch (_) {
      return null;
    }
  }

  /// 提取作业数据：把 E听说 的私有数据拷贝到本应用外部私有目录（任何 Android 版本均可读）
  /// 返回 (成功?, 消息)
  static Future<(bool, String)> extractEtsData() async {
    if (!Platform.isAndroid) return (false, '仅 Android 需要');
    final probe = await ShellService.probe();
    if (probe == null || (!probe.root && !probe.shizuku)) {
      return (false, '没有可用通道：请开启 Root / Shizuku（或在设置中重新启用通道开关）');
    }

    // 确认真实源目录（resource 子目录优先，退回上层）
    final srcProbe = await exec(
      "test -d '$etsSourceBase/resource' && echo resource",
    );
    final src = (srcProbe != null && srcProbe.exit == 0)
        ? '$etsSourceBase/resource'
        : etsSourceBase;

    // 目标：本应用外部私有目录（shell/root 均可写，应用自己永远可读）
    Directory? ext = await getExternalStorageDirectory();
    ext ??= await getApplicationDocumentsDirectory();
    final dst = p.join(ext.path, 'ets_data');

    // 清旧副本再拷贝（-a 保留结构；目标目录权限放开，保证应用可读）
    final cmd =
        "rm -rf '$dst' && mkdir -p '$dst' && cp -a '$src/.' '$dst/'"
        " && find '$dst' -type d -exec chmod 777 {} + 2>/dev/null"
        " && find '$dst' -type f -exec chmod 666 {} + 2>/dev/null"
        " && echo EXTRACT_OK";
    final r = await exec(cmd);
    if (r == null) return (false, '提权通道调用失败');
    if (r.exit != 0 || !r.out.contains('EXTRACT_OK')) {
      final detail = r.err.trim().isEmpty ? r.out.trim() : r.err.trim();
      return (false, '提取失败（via ${r.via}）：$detail');
    }

    // 指向副本并重新扫描
    SettingsService.I.setAndroidRoot(dst);
    await EtsDataService.I.rescan(silent: true);
    final n = EtsDataService.I.entries.length;
    return (true, '提取成功（via ${r.via}）→ 发现 $n 项作业');
  }

  /// 刷新作业数据：作业页「刷新」按钮的统一入口。
  /// Android 且有可用提权通道时先提取再扫描，否则直接扫描现有目录。
  static Future<(bool, String)> refresh() async {
    if (Platform.isAndroid) {
      final pr = await probe();
      if (pr != null && (pr.root || pr.shizuku)) {
        final r = await extractEtsData();
        if (r.$1) return r;
        // 提取失败也照常扫一遍现有目录，别让用户看到空列表
        await EtsDataService.I.rescan(silent: true);
        return (false, '${r.$2}；已按现有目录刷新');
      }
    }
    await EtsDataService.I.rescan(silent: true);
    return (true, '已刷新，共 ${EtsDataService.I.entries.length} 项作业');
  }
}
