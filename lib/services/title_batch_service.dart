import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/ets_models.dart';
import 'ai_service.dart';
import 'ets_data_service.dart';
import 'settings_service.dart';

/// 一键批量生成缺失标题：
/// 把所有未 AI 生成过标题的作业打包进【一次】请求，AI 返回 JSON 映射后统一应用
class TitleBatchService {
  static bool running = false;

  static Future<({int total, int ok, String error})> run({
    ValueChanged<int>? onProgress,
  }) async {
    if (running) {
      return (total: 0, ok: 0, error: '已有批量任务在进行');
    }
    running = true;
    try {
      final s = SettingsService.I;
      if (!s.aiReady) {
        return (total: 0, ok: 0, error: '未配置可用模型：请先到设置选择模型并填写 API Key');
      }
      final entries = EtsDataService.I.entries;
      final targets = <HomeworkEntry>[];
      for (final e in entries) {
        if (e.titleSource == TitleSource.ai) continue;
        final key = e.content?.stid ?? e.paper?.tzid ?? '';
        if (key.isEmpty) continue;
        targets.add(e);
      }
      if (targets.isEmpty) {
        return (total: 0, ok: 0, error: '所有作业都已有 AI 标题');
      }

      final sb = StringBuffer();
      sb.writeln('以下是若干英语听说作业的编号和内容片段。');
      if (s.grade.isNotEmpty || s.region.isNotEmpty) {
        sb.writeln(
          '背景：${s.grade.isEmpty ? '' : s.grade}'
          '${s.region.isEmpty ? '' : '（${s.region}）'}英语听说考试。',
        );
      }
      sb.writeln('请为每个编号起一个简短中文标题（不超过 18 字，含单元/话题信息更佳）。');
      sb.writeln('严格只输出 JSON 对象：{"编号":"标题",...}，不要任何其他文字。');
      for (var i = 0; i < targets.length; i++) {
        final e = targets[i];
        final key = e.content?.stid ?? e.paper?.tzid ?? '';
        var snippet = e.content?.text ?? '';
        if (snippet.isEmpty && e.paper != null) {
          snippet =
              e.paper!.sections.firstOrNull?.items.firstOrNull?.text ?? '';
        }
        snippet = snippet
            .replaceAll('</br>', ' ')
            .replaceAll(RegExp(r'<[^>]+>'), '')
            .trim();
        if (snippet.length > 160) snippet = snippet.substring(0, 160);
        sb.writeln('[$key] ${e.structure.label}：$snippet');
        onProgress?.call(i + 1);
      }

      final (out, _) = await AiService.I.chatWithFailover(
        messages: [
          {
            'role': 'system',
            'content': '你是作业标题整理助手。只输出合法 JSON 对象，键为输入编号，值为不超过 18 字的简短中文标题。',
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
        return (
          total: targets.length,
          ok: 0,
          error:
              'AI 返回格式无法解析：${out.trim().substring(0, out.length.clamp(0, 200))}',
        );
      }
      text = text.substring(f1, f2 + 1);
      final Map<String, dynamic> parsed;
      try {
        parsed = (jsonDecode(text) as Map).cast<String, dynamic>();
      } catch (_) {
        return (total: targets.length, ok: 0, error: 'AI 返回 JSON 解析失败');
      }
      var ok = 0;
      final toSave = <String, String>{};
      for (final e in targets) {
        final key = e.content?.stid ?? e.paper?.tzid ?? '';
        final t = '${parsed[key] ?? ''}'.trim();
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
