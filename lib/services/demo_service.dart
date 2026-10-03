import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'settings_service.dart';

/// 内置演示作业：首启从 assets 拷贝到应用文档目录，供新手教程参考。
/// 教程完成后从扫描根中隐藏（设置里可随时重新显示）。
class DemoService {
  static const _assetFiles = [
    'assets/demo/demo/Demo单词跟读/content.json',
    'assets/demo/demo/Demo单词跟读/material/content.wav',
    'assets/demo/demo/Demo三问五答/content.json',
    'assets/demo/demo/Demo三问五答/info.json',
  ];

  /// 演示数据根目录
  static Future<String> demoRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    return p.join(docs.path, 'ets_demo');
  }

  /// 拷贝演示数据（幂等），并把根目录回填到设置供扫描
  static Future<void> prepare() async {
    try {
      final root = await demoRoot();
      for (final asset in _assetFiles) {
        // assets/demo/demo/XXX → <root>/XXX
        final rel = asset.substring('assets/demo/demo/'.length);
        final data = await rootBundle.load(asset);
        final f = File(p.join(root, rel));
        f.parent.createSync(recursive: true);
        f.writeAsBytesSync(data.buffer.asUint8List(), flush: true);
      }
      SettingsService.I.demoRootPath = root;
    } catch (_) {
      // 演示数据失败不影响主流程
    }
  }
}
