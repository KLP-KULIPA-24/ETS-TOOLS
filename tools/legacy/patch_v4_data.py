import io

# ---------- ets_data_service.dart ----------
p = 'lib/services/ets_data_service.dart'
s = io.open(p, encoding='utf-8').read()

s = s.replace('''import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;''', '''import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';''')

# rescan：AI 标题覆盖 + 状态按文件夹计数
s = s.replace('''    final roots = SettingsService.I.activeRoots;
    for (final root in roots) {
      try {
        final dir = Directory(root);
        if (!dir.existsSync()) {
          rootStatus[root] = '目录不存在';
          continue;
        }
        final found = await compute(_scanRoot, root);
        entries.addAll(found);
        rootStatus[root] = '已扫描 ${found.length} 项';
      } catch (e) {
        rootStatus[root] = '扫描失败: $e';
        lastError = '$e';
      }
    }''', '''    final aiTitles = await loadAiTitles();
    final roots = SettingsService.I.activeRoots;
    for (final root in roots) {
      try {
        final dir = Directory(root);
        if (!dir.existsSync()) {
          rootStatus[root] = '目录不存在';
          continue;
        }
        final found = await compute(_scanRoot, root);
        // 应用 AI 生成的标题（titleSource=ai）
        for (var i = 0; i < found.length; i++) {
          final e = found[i];
          final key = e.content?.stid ?? e.paper?.tzid ?? '';
          final t = aiTitles[key];
          if (t != null && t.isNotEmpty) {
            found[i] = HomeworkEntry(
              uid: e.uid,
              dir: e.dir,
              mtime: e.mtime,
              content: e.content,
              paper: e.paper,
              title: t,
              titleSource: TitleSource.ai,
            );
          }
        }
        entries.addAll(found);
        final folderCount = computeGroups(found).length;
        rootStatus[root] = '已扫描 $folderCount 个文件夹';
      } catch (e) {
        rootStatus[root] = '扫描失败: $e';
        lastError = '$e';
      }
    }''')

# 对话跟读等自适应标题加类型后缀
s = s.replace('''    } else {
      // 二级：自适应
      title = unit.adaptiveTitle();
      source = title.startsWith('作业 ') ? TitleSource.fallback : TitleSource.adaptive;
    }
    return HomeworkEntry(
      uid: uid,''', '''    } else {
      // 二级：自适应（无具体标题时补类型后缀，便于区分）
      title = unit.adaptiveTitle();
      if (structure == EtsStructure.repeatDialogue) {
        title = '$title（对话跟读）';
      } else if (structure == EtsStructure.unknown) {
        title = '$title（未知题型）';
      }
      source = title.startsWith('作业 ') ? TitleSource.fallback : TitleSource.adaptive;
    }
    return HomeworkEntry(
      uid: uid,''')

# AI 标题缓存读写
s = s.replace('''  /// 测试用：扫描单个根目录（公开包装）''', '''  /// AI 批量生成的标题缓存：<stid/tzid, 标题>
  static Future<String> aiTitlesPath() async {
    final docs = await getApplicationDocumentsDirectory();
    return p.join(docs.path, 'ai_titles.json');
  }

  static Future<Map<String, String>> loadAiTitles() async {
    try {
      final f = File(await aiTitlesPath());
      if (!f.existsSync()) return {};
      final j = jsonDecode(f.readAsStringSync()) as Map;
      return j.map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveAiTitles(Map<String, String> titles) async {
    final f = File(await aiTitlesPath());
    final old = await loadAiTitles();
    old.addAll(titles);
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(jsonEncode(old));
  }

  /// 测试用：扫描单个根目录（公开包装）''')

# jsonDecode/jsonEncode 需要 dart:convert
s = s.replace("import 'dart:collection';\nimport 'dart:io';",
              "import 'dart:collection';\nimport 'dart:convert';\nimport 'dart:io';")

io.open(p, 'w', encoding='utf-8').write(s)
print('data service ok')

# ---------- 标题批量生成服务 ----------
svc = '''import 'package:flutter/foundation.dart';

import '../models/ets_models.dart';
import 'ai_service.dart';
import 'ets_data_service.dart';
import 'settings_service.dart';

/// 一键批量生成缺失标题：把所有未 AI 生成过标题的作业
/// 打包进一次请求（不是逐个发送），AI 返回 JSON 映射后统一应用
class TitleBatchService {
  static bool running = false;

  static Future<({int total, int ok, String error})> run(
      {ValueChanged<int>? onProgress}) async {
    if (running) {
      return (total: 0, ok: 0, error: '已有批量任务在进行');
    }
    running = true;
    try {
      final s = SettingsService.I;
      if (!s.aiReady) {
        return (
          total: 0,
          ok: 0,
          error: '未配置可用模型：请先到设置选择模型并填写 API Key'
        );
      }
      final entries = EtsDataService.I.entries;
      final targets = <HomeworkEntry>[];
      for (final e in entries) {
        if (e.titleSource == TitleSource.ai) continue;
        final key = e.content?.stid ?? e.paper?.tzid ?? '';
        if (key.isEmpty) continue;
        // 素材片段（截断）
        final snippet = e.content != null
            ? e.content!.text.replaceAll('</br>', ' ')
            : (e.paper?.sections.firstOrNull?.items.firstOrNull?.text ?? '');
        targets.add(e);
      }
      if (targets.isEmpty) return (total: 0, ok: 0, error: '所有作业都已有 AI 标题');

      final sb = StringBuffer();
      sb.writeln('以下是若干英语听说作业的编号和内容片段。');
      sb.writeln('请为每个编号起一个简短中文标题（不超过 18 字，含单元/话题信息更佳）。');
      sb.writeln('严格只输出 JSON 对象：{"编号":"标题",...}，不要任何其他文字。');
      for (var i = 0; i < targets.length; i++) {
        final e = targets[i];
        final key = e.content?.stid ?? e.paper?.tzid ?? '';
        var snippet = e.content?.text ?? '';
        if (snippet.isEmpty && e.paper != null) {
          snippet = e.paper!.sections
                  .firstOrNull?.items.firstOrNull?.text ??
              '';
        }
        snippet = snippet
            .replaceAll('</br>', ' ')
            .replaceAll(RegExp(r'<[^>]+>'), '')
            .trim();
        if (snippet.length > 160) snippet = snippet.substring(0, 160);
        sb.writeln('[\$key] \${e.structure.label}：\$snippet');
        onProgress?.call(i + 1);
      }

      final (out, _) = await AiService.I.chatWithFailover(
        messages: [
          {
            'role': 'system',
            'content': '你是作业标题整理助手。只输出合法 JSON 对象，键为输入编号，值为不超过 18 字的简短中文标题。'
          },
          {'role': 'user', 'content': sb.toString()},
        ],
        temperature: 0.2,
      );

      // 解析 JSON（容忍 ```json 包裹）
      var text = out.trim();
      final f1 = text.indexOf('{');
      final f2 = text.lastIndexOf('}');
      if (f1 < 0 || f2 <= f1) {
        return (total: targets.length, ok: 0, error: 'AI 返回格式无法解析：\${out.trim().substring(0, out.length.clamp(0, 200))}');
      }
      text = text.substring(f1, f2 + 1);
      final Map parsed;
      try {
        parsed = jsonDecodeText(text);
      } catch (_) {
        return (total: targets.length, ok: 0, error: 'AI 返回 JSON 解析失败');
      }
      var ok = 0;
      final toSave = <String, String>{};
      for (final e in targets) {
        final key = e.content?.stid ?? e.paper?.tzid ?? '';
        final t = '\${parsed[key] ?? ''}'.trim();
        if (t.isNotEmpty) {
          toSave[key] = t;
          ok++;
        }
      }
      await EtsDataService.saveAiTitles(toSave);
      await EtsDataService.I.rescan();
      return (total: targets.length, ok: ok, error: '');
    } finally {
      running = false;
    }
  }
}

/// jsonDecode 包装（便于扩展容错）
Map<String, dynamic> jsonDecodeText(String text) {
  final v = const JsonDecoder().convert(text);
  return (v as Map).cast<String, dynamic>();
}
'''
io.open('lib/services/title_batch_service.dart', 'w', encoding='utf-8').write(svc)
print('title batch service ok')
