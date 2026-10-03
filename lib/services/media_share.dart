import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 图片/视频等媒体文件的分享与下载
///
/// ⚠️ Windows 不要用 file_selector 的原生另存为对话框：本应用是
/// 自定义标题栏窗口（titleBarStyle hidden + 自绘 chrome），原生模态对话框
/// 在该窗口下会挂起且不可见，表现为整个应用「未响应」。
/// 下载 = 直接保存到系统「下载/E听说助手/」目录（免对话框、零卡死）。
class MediaShare {
  MediaShare._();

  /// 分享文件（Android 弹系统分享面板，可发微信；Windows 无系统分享）
  static Future<void> share(
    BuildContext context,
    String path, {
    String? text,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!Platform.isAndroid && !Platform.isIOS) {
      _toast(messenger, '当前平台无系统分享，可用「保存到下载」');
      return;
    }
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], text: text ?? ''),
      );
    } catch (e) {
      _toast(messenger, '分享失败：$e');
    }
  }

  /// 清洗为合法文件名（去掉 Windows 非法字符）
  static String sanitize(String name) => name
      .replaceAll(RegExp(r'[\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// 下载：保存到「下载/E听说助手/」（重名自动加序号），并提示路径
  /// [targetName] 自定义保存文件名（含扩展名）；默认用原文件名
  static Future<void> saveAs(
    BuildContext context,
    String path, {
    String? targetName,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      Directory? base;
      if (Platform.isWindows) {
        base = await getDownloadsDirectory();
      }
      base ??= await getExternalStorageDirectory();
      base ??= await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(base.path, 'E听说助手'))
        ..createSync(recursive: true);
      final fname = sanitize(targetName ?? p.basename(path));
      final stem = p.basenameWithoutExtension(fname);
      final ext = p.extension(fname).isEmpty
          ? p.extension(path)
          : p.extension(fname);
      var target = p.join(dir.path, '$stem$ext');
      var i = 1;
      while (File(target).existsSync()) {
        target = p.join(dir.path, '$stem($i)$ext');
        i++;
      }
      await File(path).copy(target);
      _toast(messenger, '已保存到：$target');
    } catch (e) {
      _toast(messenger, '保存失败：$e');
    }
  }

  /// 复制文件路径到剪贴板
  static Future<void> copyPath(BuildContext context, String path) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: path));
    _toast(messenger, '已复制路径');
  }

  /// 底部弹层：分享 / 保存到下载 / 复制路径（按平台裁剪）
  /// [targetName] 保存时的文件名（套卷名-题型-题目-原名）
  static Future<void> showSheet(
    BuildContext context,
    String path, {
    String title = '媒体',
    String? targetName,
  }) async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                p.basename(path),
                style: const TextStyle(fontSize: 12),
              ),
            ),
            if (Platform.isAndroid || Platform.isIOS)
              ListTile(
                leading: const Icon(Icons.share_rounded),
                title: const Text('分享'),
                subtitle: const Text('发送到微信 / 其他应用'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  share(context, path);
                },
              ),
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: const Text('保存到下载'),
              subtitle: const Text('保存到「下载/E听说助手」文件夹'),
              onTap: () {
                Navigator.of(ctx).pop();
                saveAs(context, path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_copy_rounded),
              title: const Text('复制路径'),
              onTap: () {
                Navigator.of(ctx).pop();
                copyPath(context, path);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static void _toast(ScaffoldMessengerState messenger, String msg) {
    messenger.showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }
}
