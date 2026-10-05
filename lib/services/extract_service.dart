import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'ets_data_service.dart';
import 'settings_service.dart';

/// 数据提取通道（四模式，与 ETSToolbox 对齐）：
/// shizuku（推荐）/ root（最高权限）/ directRead（零提权直读）/ saf（授权目录）
// 顺序即面板展示与自动刷新链的优先级：SAF 最傻瓜（系统选择器点两下），
// 直读次之，再是 Shizuku，最后 Root。学生党不会装提权工具，所以 SAF 排第一。
enum ExtractMode { saf, directRead, shizuku, root }

extension ExtractModeX on ExtractMode {
  String get label => switch (this) {
    ExtractMode.saf => 'SAF',
    ExtractMode.directRead => 'DIRECT_READ',
    ExtractMode.shizuku => 'SHIZUKU',
    ExtractMode.root => 'ROOT',
  };

  String get title => switch (this) {
    ExtractMode.shizuku => 'Shizuku 提权',
    ExtractMode.root => 'Root 超级权限',
    ExtractMode.directRead => '零提权直读',
    ExtractMode.saf => '存储访问框架',
  };

  String get desc => switch (this) {
    ExtractMode.shizuku => '借助 Shizuku 获得高级 API，在非 Root 设备上实现数据提取。真机推荐。',
    ExtractMode.root => '通过 Root 权限直接访问应用私有文件，兼容性最好、权限最高。',
    ExtractMode.directRead => '部分 ROM / 低版本安卓可直接读取 Android/data，无需任何提权工具。',
    ExtractMode.saf =>
      '用系统存储访问框架授权 E听说 数据目录，免 Root、免电脑，全程系统弹窗。选 Android/data 或它里面任意一层都可以。',
  };
}

/// 四通道提取状态与执行
class ExtractService {
  static const _channel = MethodChannel('eets/shell');

  /// E听说 在 Android 上的真实数据源
  static const etsSourceBase =
      '/storage/emulated/0/Android/data/com.ets100.secondary/files/Download/ETS_secondary';

  /// 四模式就绪状态（probe 结果缓存）
  static ({
    bool root,
    bool shizuku,
    bool shizukuInstalled,
    bool directRead,
    bool saf,
  })?
  lastProbe;

  /// 一次探测：四通道全部状态
  static Future<
    ({
      bool root,
      bool shizuku,
      bool shizukuInstalled,
      bool directRead,
      bool saf,
    })?
  >
  probeAll() async {
    if (!Platform.isAndroid) return null;
    try {
      final r = await _channel.invokeMethod<Map>('probe');
      final raw = (
        root: r?['root'] == true,
        shizuku: r?['shizuku'] == true,
        shizukuInstalled: r?['shizukuInstalled'] == true,
        directRead: r?['directRead'] == true,
        saf: r?['saf'] == true,
      );
      // 用户设置里的通道开关只约束提权两通道
      lastProbe = (
        root: raw.root && SettingsService.I.useRoot,
        shizuku: raw.shizuku && SettingsService.I.useShizuku,
        shizukuInstalled: raw.shizukuInstalled && SettingsService.I.useShizuku,
        directRead: raw.directRead,
        saf: raw.saf,
      );
      return lastProbe;
    } catch (_) {
      lastProbe = (
        root: false,
        shizuku: false,
        shizukuInstalled: false,
        directRead: false,
        saf: false,
      );
      return lastProbe;
    }
  }

  /// 提取目的目录（本应用外部私有 ets_data）
  static Future<String> _dst() async {
    Directory? ext = await getExternalStorageDirectory();
    ext ??= await getApplicationDocumentsDirectory();
    return p.join(ext.path, 'ets_data');
  }

  static Future<void> _finishExtract() async {
    SettingsService.I.setAndroidRoot(await _dst());
    await EtsDataService.I.rescan(silent: true);
  }

  /// 按模式提取。返回 (成功?, 消息)
  static Future<(bool, String)> extract(ExtractMode mode) async {
    if (!Platform.isAndroid) return (false, '仅 Android 需要');
    final dst = await _dst();
    switch (mode) {
      case ExtractMode.root || ExtractMode.shizuku:
        final r = await _channel.invokeMethod<Map>('exec', {
          'cmd':
              "test -d '$etsSourceBase/resource' && echo resource; "
              "rm -rf '$dst' && mkdir -p '$dst' && "
              "cp -a '$etsSourceBase/resource/.' '$dst/' 2>/dev/null || "
              "cp -a '$etsSourceBase/.' '$dst/'; "
              "find '$dst' -type d -exec chmod 777 {} + 2>/dev/null; "
              "find '$dst' -type f -exec chmod 666 {} + 2>/dev/null; "
              'echo EXTRACT_OK',
        });
        if (r == null) return (false, '提权通道调用失败');
        final exit = (r['exit'] as num?)?.toInt() ?? -1;
        final out = '${r['out']}';
        if (exit != 0 || !out.contains('EXTRACT_OK')) {
          return (false, '提取失败（via ${r['via']}）：${r['err'] ?? out}');
        }
        await _finishExtract();
        final n = EtsDataService.I.entries.length;
        return (true, '提取成功（via ${r['via']}）→ 发现 $n 项作业');

      case ExtractMode.directRead:
        final r = await _channel.invokeMethod<Map>('directCopy', {'dst': dst});
        final ok = r?['ok'] == true;
        if (!ok) return (false, '${r?['msg'] ?? '直读不可用'}');
        await _finishExtract();
        final n = EtsDataService.I.entries.length;
        return (true, '${r?['msg'] ?? '直读成功'} → 发现 $n 项作业');

      case ExtractMode.saf:
        final r = await _channel.invokeMethod<Map>('safCopy', {'dst': dst});
        final ok = r?['ok'] == true;
        if (!ok) return (false, '${r?['msg'] ?? 'SAF 未授权'}');
        await _finishExtract();
        final n = EtsDataService.I.entries.length;
        return (true, '${r?['msg'] ?? 'SAF 提取成功'} → 发现 $n 项作业');
    }
  }

  /// 发起 SAF 授权（系统目录选择弹窗）。返回 ok/cancelled/unavailable
  static Future<String> requestSaf() async {
    try {
      return '${await _channel.invokeMethod<String>('safPick')}';
    } catch (_) {
      return 'unavailable';
    }
  }

  /// 发起 Shizuku 授权。返回 ok/requested/unavailable
  static Future<String> requestShizuku() async {
    try {
      return '${await _channel.invokeMethod<String>('requestShizuku')}';
    } catch (_) {
      return 'unavailable';
    }
  }

  /// 刷新（作业页 FAB）：优先用用户指定的通道（SAF 卡上点过「开始提取」的那个），
  /// 失败再按可用顺序降级；全部不可用则直接扫描现有目录
  static Future<(bool, String)> refresh() async {
    if (!Platform.isAndroid) {
      await EtsDataService.I.rescan(silent: true);
      return (true, '已刷新，共 ${EtsDataService.I.entries.length} 项作业');
    }
    final pr = await probeAll();
    final pref = ExtractMode.values
        .where((m) => m.name == SettingsService.I.extractModePref)
        .firstOrNull;
    // 自动链优先级 = ExtractMode.values 的顺序：SAF（系统选择器，点两下）
    // → 直读 → Shizuku → Root。学生党不会装提权工具，所以最傻瓜的排第一。
    final auto = <ExtractMode>[
      if (pr?.saf == true) ExtractMode.saf,
      if (pr?.directRead == true) ExtractMode.directRead,
      if (pr?.shizuku == true) ExtractMode.shizuku,
      if (pr?.root == true) ExtractMode.root,
    ];
    // 用户指定优先（即使探测未就绪也先试一次，失败自动降级到其他通道）
    final attempts = <ExtractMode>[?pref, ...auto.where((m) => m != pref)];
    String lastMsg = '';
    for (final m in attempts) {
      final r = await extract(m);
      if (r.$1) return r;
      lastMsg = '${m.label}: ${r.$2}';
    }
    await EtsDataService.I.rescan(silent: true);
    if (attempts.isEmpty) {
      return (false, '暂无可用通道（可在「选择工作授权模式」中启用）；已按现有目录刷新');
    }
    return (false, '$lastMsg；已按现有目录刷新');
  }
}
