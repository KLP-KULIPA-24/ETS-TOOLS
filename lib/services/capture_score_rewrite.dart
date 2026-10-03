import 'dart:convert';

import 'capture_rewrite.dart';

/// 成绩**响应**改写（2026-10-01 抓包实锤）。
///
/// 关键事实（第二次 Win 抓包）：
/// - 所有响应都是**明文 JSON 数组**（不是 base64 信封）：`[{"msg":"成功","code":0,"body":{…}}]`
/// - 界面展示的分数来自响应，不是请求：
///   · `m/set/get-score-detail` → body.score[].real_score/standard_score/detail(JSON串)
///     + body.avg_point + body.dimension_score
///   · `g/set/list` → body.score[].point/avg_point/total_point（作业列表总分）
///   · `m/audio/sync-v2` 响应 → body.point/real_score（提交后即时反馈）
/// - 每条 score 项自带 `total_point`（该小题满分），所以作业满分可在响应内自洽求出。
///
/// 因此"改分"要双管齐下：改请求（写库，影响老师看到的）＋改响应（本地显示）。

class ScoreResponseResult {
  final String bodyText;
  final bool changed;
  final String? note;
  const ScoreResponseResult(this.bodyText, this.changed, this.note);
}

/// 改写成绩相关接口的响应体（明文 JSON）
ScoreResponseResult rewriteScoreResponse(
  String rawText,
  CaptureRules rules, {
  String? route,
}) {
  if (!rules.scoreOn) return ScoreResponseResult(rawText, false, null);
  dynamic root;
  try {
    root = jsonDecode(rawText);
  } catch (_) {
    return ScoreResponseResult(rawText, false, null);
  }
  if (root is! List || root.isEmpty) {
    return ScoreResponseResult(rawText, false, null);
  }
  var changed = false;
  final notes = <String>[];

  for (final item in root) {
    if (item is! Map) continue;
    final body = item['body'];
    if (body is! Map) continue;

    // 统一处理 score[]：详情页项（real_score/detail/entity_id）与
    // 列表项（point/set_id/first_column_id）字段不同，按字段驱动而非分支
    final scoreList = body['score'];
    if (scoreList is List && scoreList.isNotEmpty) {
      // 作业满分 = 各小题满分之和（响应自洽，不依赖引擎学习）
      var full = 0.0;
      for (final s in scoreList) {
        if (s is Map) full += _num(s['total_point']) ?? 0;
      }
      if (full > 0) {
        for (final s in scoreList) {
          if (s is! Map) continue;
          final mark = _num(s['total_point']) ?? 0;
          if (mark <= 0) continue;
          final detail = _parseDetail(s['detail']);
          final category = '${(detail?['category'] ?? '')}';
          final newScore = _calcScore(rules, category, mark, full);
          // 详情页项：real_score / standard_score + detail 内各项
          for (final k in const ['real_score', 'standard_score']) {
            if (s.containsKey(k)) {
              s[k] = _typed(s[k], newScore);
              changed = true;
            }
          }
          if (detail != null) {
            _applyDetail(detail, newScore);
            s['detail'] = jsonEncode(detail);
            changed = true;
          }
          // 列表项：point / avg_point
          if (s.containsKey('point')) {
            s['point'] = _typed(s['point'], newScore);
            changed = true;
            notes.add(
              '列表 ${mark.toStringAsFixed(0)}→'
              '${newScore.toStringAsFixed(1)}',
            );
          }
          if (s.containsKey('avg_point') && !s.containsKey('detail')) {
            s['avg_point'] = _typed(s['avg_point'], newScore);
          }
        }
      }
      // 汇总分（详情页 avg_point = 各小题得分和）
      if (body.containsKey('avg_point')) {
        var sum = 0.0;
        var any = false;
        for (final s in scoreList) {
          if (s is! Map) continue;
          final v = _num(s['real_score']) ?? _num(s['point']);
          if (v != null) {
            sum += v;
            any = true;
          }
        }
        if (any) {
          body['avg_point'] = _typed(body['avg_point'], _round1(sum));
          changed = true;
        }
      }
      // 维度分（详情页顶部雷达图）
      final dim = body['dimension_score'];
      if (dim is Map) {
        var sum = 0.0;
        var cnt = 0;
        for (final s in scoreList) {
          if (s is! Map) continue;
          final v = _num(s['real_score']) ?? _num(s['point']);
          if (v != null) {
            sum += v;
            cnt++;
          }
        }
        final each = _round1(cnt > 0 ? sum / cnt : 0);
        for (final k in const [
          'fluency_score',
          'integrity_score',
          'accuracy_score',
          'standard_score',
          'stress_pronunciation_score',
        ]) {
          if (dim.containsKey(k)) {
            dim[k] = _typed(dim[k], each);
            changed = true;
          }
        }
      }
    }
  }

  if (!changed) return ScoreResponseResult(rawText, false, null);
  return ScoreResponseResult(
    jsonEncode(root),
    true,
    notes.isEmpty ? '按规则改写响应' : notes.join('；'),
  );
}

/// 计算一道小题该拿多少分
double _calcScore(
  CaptureRules rules,
  String category,
  double mark,
  double full,
) {
  if (rules.advancedOn) {
    final ov = rules.categoryScores[category];
    if (ov != null) return _round1(ov);
  }
  if (full <= 0) return mark;
  return _round1(mark * rules.targetScore / full);
}

/// 把 detail 里的 total_score 与四分项改成 newScore（保持原类型）
void _applyDetail(Map detail, double newScore) {
  detail['total_score'] = _typed(detail['total_score'], newScore);
  if (detail.containsKey('real_score')) {
    detail['real_score'] = _typed(detail['real_score'], newScore);
  }
  for (final k in kSubScoreKeys) {
    if (detail.containsKey(k)) {
      detail[k] = _typed(detail[k], newScore);
    }
  }
}

Map? _parseDetail(dynamic raw) {
  if (raw == null) return null;
  try {
    final v = raw is String ? jsonDecode(raw) : raw;
    return v is Map ? v : null;
  } catch (_) {
    return null;
  }
}

double? _num(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

double _round1(double v) => (v * 10).roundToDouble() / 10;

/// 保留原类型：字符串（含 "0.000000" 六位小数的分项）仍写字符串，数字仍写数字
dynamic _typed(dynamic old, double value) {
  if (old is String) {
    // 六位小数的分项保持原格式，其余一位小数
    if (old.contains('.') && old.split('.').last.length >= 3) {
      return value.toStringAsFixed(old.split('.').last.length);
    }
    return value.toStringAsFixed(1);
  }
  if (old is int) {
    return value == value.roundToDouble() ? value.round() : value;
  }
  return value;
}
