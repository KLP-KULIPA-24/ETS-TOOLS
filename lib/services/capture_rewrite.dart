import 'dart:convert';

/// E听说 API 改写器（纯函数，无 IO，可单测）。
///
/// 协议（2026-10-01 抓包实测，样本在 E:\E听说助手\抓包数据\）：
/// 请求/响应外层 `{"body": "<base64(JSON数组)>", "head": {...}}`，sign 不校验 body。
/// body 解开后是 `[{"r": "接口路由", "params": {...}}, ...]`。
/// 改分落点 `POST /m/audio/sync-v2`（每小题一次）：
/// - params.score：安卓是字符串 "0.0"，Win 是数字 0
/// - params.score_detail：JSON 套 JSON 字符串（total_score + 四分项 + category）
/// - 仅 Win 有 params.real_score / params.question_type_score（该题满分，字符串）
/// - params.client_time："YYYY-MM-DD HH:mm:ss"，完成时间候选来源
/// 双端都没有 set-use-time（用时无法上报，只能改完成时刻）。

/// 改分路由（同步小题成绩）
const String kRouteSyncV2 = 'm/audio/sync-v2';

/// 成绩详情查询路由（响应里可学习各小题满分）
const String kRouteScoreDetail = 'm/set/get-score-detail';

/// MITM 目标主机（只对该主机解密，其余全部盲转发）
const String kMitmHost = 'api.ets100.com';

/// sync-v2 请求路径片段（含 query）
const String kSyncV2Path = '/m/audio/sync-v2';

/// 各题型默认满分兜底（仅收抓包实测过的值；不在表内且学习不到满分的题原样放行）
const Map<String, double> kDefaultCategoryMarks = <String, double>{
  'read_chapter': 20, // 朗读短文/课文
  'simple_expression': 2, // 情景表达/跟读
  'topic': 24, // 话题表达
};

/// 学习不到作业满分时的兜底值（抓包样本作业满分即 60；学到真实值后自动覆盖）
const double kFallbackHomeworkFull = 60;

/// score_detail 里的四个分项（与总分同步缩放）
const List<String> kSubScoreKeys = <String>[
  'fluency_score',
  'accuracy_score',
  'integrity_score',
  'standard_score',
];

/// 改写规则（由引擎从 SettingsService 现读现用，避免配置滞后）
class CaptureRules {
  final bool scoreOn;
  final double targetScore;

  /// 高级模式：按题型精确设分（category → 每小题得分），命中即用，不走比例
  final bool advancedOn;
  final Map<String, double> categoryScores;

  final bool timeOn;

  /// 完成时刻偏移（秒，负=提前，正=延后）；UI 填的是时长，引擎换算成负偏移
  final int timeOffsetSec;

  const CaptureRules({
    required this.scoreOn,
    required this.targetScore,
    required this.advancedOn,
    required this.categoryScores,
    required this.timeOn,
    required this.timeOffsetSec,
  });

  static const CaptureRules off = CaptureRules(
    scoreOn: false,
    targetScore: 0,
    advancedOn: false,
    categoryScores: {},
    timeOn: false,
    timeOffsetSec: 0,
  );
}

/// 改写结果
class CaptureRewriteResult {
  /// 改写后的完整请求体文本（未改写时与输入相同）
  final String bodyText;
  final bool changed;

  /// 未改写/部分改写的说明（进修改页状态行）
  final List<String> notes;
  const CaptureRewriteResult(this.bodyText, this.changed, this.notes);
}

/// 从响应里学到的满分知识
class CaptureLearning {
  /// sync-v2 响应 body.total_point = 作业满分
  final double? homeworkFull;

  /// get-score-detail 响应：entity_id → 该小题满分 total_point
  final Map<String, double> entityMarks;
  const CaptureLearning(this.homeworkFull, this.entityMarks);
}

/// 路由是否就是 sync-v2：容忍前导斜杠与大小写（双端实际写法可能带 "/"）
bool _isSyncRoute(String route) {
  final r = route.trim();
  return r == kRouteSyncV2 ||
      r == '/$kRouteSyncV2' ||
      r.toLowerCase() == kRouteSyncV2 ||
      r.endsWith(kRouteSyncV2);
}

/// 改写一条 API 请求体（envelope JSON 文本）。
///
/// 只处理 sync-v2 路由；解析失败/不匹配一律原样返回（绝不弄挂作业）。
/// [homeworkFull]/[entityMark] 是引擎侧学到的满分知识（安卓请求不带满分）。
CaptureRewriteResult rewriteApiRequestBody(
  String rawBody,
  CaptureRules rules, {
  double? homeworkFull,
  double? entityMark,
  DateTime? now,
}) {
  if (!rules.scoreOn && !rules.timeOn) {
    return CaptureRewriteResult(rawBody, false, const []);
  }
  dynamic envelope;
  try {
    envelope = jsonDecode(rawBody);
  } catch (_) {
    return CaptureRewriteResult(rawBody, false, const ['请求体不是 JSON，原样放行']);
  }
  if (envelope is! Map || envelope['body'] is! String) {
    return CaptureRewriteResult(rawBody, false, const ['请求信封不识别，原样放行']);
  }
  final List<String> notes = [];
  var changed = false;
  var sawRoute = '';
  List? innerList;
  try {
    final inner = _decodeInnerBody(envelope['body'] as String);
    if (inner is! List) {
      return CaptureRewriteResult(rawBody, false, const ['body 不是数组，原样放行']);
    }
    innerList = inner;
    for (final item in inner) {
      if (item is! Map) continue;
      final route = '${item['r'] ?? ''}';
      if (route.isNotEmpty && sawRoute.isEmpty) sawRoute = route;
      if (!_isSyncRoute(route)) continue;
      final params = item['params'];
      if (params is! Map) continue;
      final r = _rewriteParams(
        params,
        rules,
        homeworkFull: homeworkFull,
        entityMark: entityMark,
        now: now,
      );
      if (r.$1) changed = true;
      if (r.$2 != null) notes.add(r.$2!);
    }
  } catch (e) {
    return CaptureRewriteResult(rawBody, false, ['改写出错已放行：$e']);
  }
  if (!changed) {
    if (notes.isEmpty && sawRoute.isNotEmpty) {
      // URL 命中但 body 路由对不上：把真实 route 报给状态卡，便于定位
      return CaptureRewriteResult(rawBody, false, ['body 路由不匹配（实际 $sawRoute）']);
    }
    return CaptureRewriteResult(rawBody, false, notes);
  }
  try {
    envelope['body'] = _encodeInnerBody(innerList);
  } catch (e) {
    return CaptureRewriteResult(rawBody, false, ['重编码失败已放行：$e']);
  }
  return CaptureRewriteResult(jsonEncode(envelope), true, notes);
}

/// 改写单个 sync-v2 params；返回（是否改动，说明）
(bool, String?) _rewriteParams(
  Map params,
  CaptureRules rules, {
  double? homeworkFull,
  double? entityMark,
  DateTime? now,
}) {
  var changed = false;
  final notes = <String>[];

  // ---- 改分 ----
  if (rules.scoreOn) {
    final detail = _parseScoreDetail(params['score_detail']);
    if (detail == null) {
      notes.add('score_detail 解析失败，该题未改分');
    } else {
      final category = '${detail['category'] ?? ''}';
      final mark =
          _asDouble(params['question_type_score']) ??
          entityMark ??
          kDefaultCategoryMarks[category];
      if (mark == null || mark <= 0) {
        notes.add('题型 $category 满分未知，该题未改分');
      } else {
        final override = rules.advancedOn
            ? rules.categoryScores[category]
            : null;
        final double newScore;
        if (override != null) {
          newScore = override;
        } else if (homeworkFull != null && homeworkFull > 0) {
          // 已知作业满分：按占比分摊（目标可超满分）
          newScore = _round1(mark * rules.targetScore / homeworkFull);
        } else {
          // 满分未知（该作业首次提交）：直接给满分，避免按假满分算出错误低分
          newScore = mark;
        }
        final total = _asDouble(detail['total_score']) ?? 0;
        detail['total_score'] = _typed(detail['total_score'], newScore);
        for (final k in kSubScoreKeys) {
          final v = _asDouble(detail[k]);
          if (v == null) continue;
          // 分项与总分同比例缩放；原分为 0 时按总分等值填充保持自洽
          final nv = total > 0 ? v * newScore / total : newScore;
          detail[k] = _typed(detail[k], _round1(nv));
        }
        params['score_detail'] = jsonEncode(detail);
        params['score'] = _typed(params['score'], newScore);
        // Win 端真实分同步覆盖（前辈做法：不让真实分露馅）
        if (params.containsKey('real_score')) {
          params['real_score'] = _typed(params['real_score'], newScore);
        }
        changed = true;
      }
    }
  }

  // ---- 改完成时刻 ----
  if (rules.timeOn) {
    final t = (now ?? DateTime.now()).add(
      Duration(seconds: rules.timeOffsetSec),
    );
    final fmt = _fmtTime(t);
    if ('${params['client_time'] ?? ''}' != fmt) {
      params['client_time'] = fmt;
      changed = true;
    }
  }

  return (changed, notes.isEmpty ? null : notes.join('；'));
}

Map? _parseScoreDetail(dynamic raw) {
  if (raw == null) return null;
  try {
    final v = raw is String ? jsonDecode(raw) : raw;
    return v is Map ? v : null;
  } catch (_) {
    return null;
  }
}

/// 保留原字段的类型习惯（安卓字符串 / Win 数字）
dynamic _typed(dynamic old, double value) {
  if (old is String) return _fmt1(value);
  if (old is int) {
    return value == value.roundToDouble() ? value.round() : value;
  }
  return value;
}

double _round1(double v) => (v * 10).roundToDouble() / 10;

String _fmt1(double v) => v.toStringAsFixed(1);

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

String _fmtTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

dynamic _decodeInnerBody(String b64) {
  final cleaned = b64.replaceAll(RegExp(r'\s'), '');
  final bytes = base64.decode(cleaned);
  return jsonDecode(utf8.decode(bytes));
}

/// 重编码 inner 数组为 base64（单行，服务端按标准 base64 解码）
String _encodeInnerBody(dynamic inner) {
  return base64.encode(utf8.encode(jsonEncode(inner)));
}

/// 从响应体（envelope JSON 文本）学习满分知识。
/// [path] 是请求路径，用于区分 sync-v2 与 get-score-detail。
CaptureLearning? learnFromResponseBody(String path, String rawText) {
  try {
    // 抓包实锤：响应是**明文 JSON 数组** `[{"msg":"成功","code":0,"body":{…}}]`，
    // 不是 base64 信封。两种都兼容。
    dynamic root = jsonDecode(rawText);
    List items;
    if (root is List) {
      items = root;
    } else if (root is Map && root['body'] is String) {
      final inner = _decodeInnerBody(root['body'] as String);
      if (inner is! List) return null;
      items = inner;
    } else {
      return null;
    }
    if (items.isEmpty) return null;

    if (path.contains(kSyncV2Path)) {
      for (final item in items) {
        if (item is! Map) continue;
        final b = item['body'];
        if (b is! Map) continue;
        final full = _asDouble(b['total_point']);
        if (full != null && full > 0) return CaptureLearning(full, const {});
      }
    } else if (path.contains(kRouteScoreDetail)) {
      // 明文结构：body.score[] 每项含 entity_id + total_point（各小题满分）
      var sum = 0.0;
      final marks = <String, double>{};
      for (final item in items) {
        if (item is! Map) continue;
        final b = item['body'];
        if (b is! Map) continue;
        final scoreList = b['score'];
        if (scoreList is! List) continue;
        for (final s in scoreList) {
          if (s is! Map) continue;
          final eid = '${s['entity_id'] ?? ''}';
          final p = _asDouble(s['total_point']);
          if (p != null && p > 0) {
            sum += p;
            if (eid.isNotEmpty) marks[eid] = p;
          }
        }
      }
      if (marks.isNotEmpty) return CaptureLearning(sum, marks);
    }
  } catch (_) {}
  return null;
}
