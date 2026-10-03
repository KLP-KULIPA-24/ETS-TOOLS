import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:e_ets_helper/services/capture_rewrite.dart';

/// 用抓包真实样本构造的样本体（安卓：分数为字符串；Win：数字 + real_score/question_type_score）
final String androidBody =
    '{"body":"$_androidB64","head":{"pid":"androidV3","sign":"x"}}';
final String winBody = '{"body":"$_winB64","head":{"pid":"grlx","sign":"y"}}';

final String _androidInner = jsonEncode([
  {
    'r': kRouteSyncV2,
    'params': {
      'resource_id': '1767',
      'entity_id': '253909',
      'order': '1',
      'score': '0.0',
      'correct': 0,
      'auto_submit': 1,
      'client_time': '2026-10-01 11:22:27',
      'score_detail': jsonEncode({
        'total_score': '0.0',
        'fluency_score': '0.0',
        'accuracy_score': '0.0',
        'integrity_score': '0.0',
        'standard_score': '0.0',
        'category': 'read_chapter',
        'rate_scale': 1,
      }),
    },
  },
]);

final String _winInner = jsonEncode([
  {
    'r': kRouteSyncV2,
    'params': {
      'resource_id': '1767',
      'entity_id': '253909',
      'order': '1',
      'score': 0,
      'real_score': 0,
      'question_type_score': '20',
      'client_time': '2026-10-01 11:33:17',
      'score_detail': jsonEncode({
        'total_score': 0,
        'fluency_score': 0,
        'accuracy_score': 0,
        'integrity_score': 0,
        'standard_score': 0,
        'category': 'read_chapter',
      }),
    },
  },
]);

final String _androidB64 = base64.encode(utf8.encode(_androidInner));
final String _winB64 = base64.encode(utf8.encode(_winInner));

Map innerOf(String bodyText) {
  final env = jsonDecode(bodyText) as Map;
  return (jsonDecode(
        utf8.decode(base64.decode(env['body'] as String)),
      ) as List).first
      as Map;
}

CaptureRules rules({
  bool scoreOn = true,
  double target = 60,
  bool advanced = false,
  Map<String, double> categoryScores = const {},
  bool timeOn = false,
  int offsetSec = 0,
}) => CaptureRules(
  scoreOn: scoreOn,
  targetScore: target,
  advancedOn: advanced,
  categoryScores: categoryScores,
  timeOn: timeOn,
  timeOffsetSec: offsetSec,
);

void main() {
  test('安卓样本：目标60/满分60 → 朗读题拿满 20，字符串类型保持，分项等值填充', () {
    final r = rewriteApiRequestBody(
      androidBody,
      rules(),
      homeworkFull: 60,
      now: DateTime(2026, 10, 1, 12),
    );
    expect(r.changed, isTrue);
    final p = innerOf(r.bodyText)['params'] as Map;
    expect(p['score'], '20.0'); // 字符串类型保持
    final d = jsonDecode(p['score_detail'] as String) as Map;
    expect(d['total_score'], '20.0');
    expect(d['fluency_score'], '20.0'); // 原分 0 → 等值填充
    expect(d['category'], 'read_chapter');
  });

  test('比例折算：目标 30/满分 60 → 朗读 10.0', () {
    final r = rewriteApiRequestBody(
      androidBody,
      rules(target: 30),
      homeworkFull: 60,
    );
    final p = innerOf(r.bodyText)['params'] as Map;
    expect(p['score'], '10.0');
  });

  test('离谱目标：目标 120/满分 60 → 每题双倍分（不封顶）', () {
    final r = rewriteApiRequestBody(
      androidBody,
      rules(target: 120),
      homeworkFull: 60,
    );
    final p = innerOf(r.bodyText)['params'] as Map;
    expect(p['score'], '40.0');
  });

  test('Win 样本：question_type_score 当满分，数字类型保持，real_score 同步覆盖', () {
    final r = rewriteApiRequestBody(
      winBody,
      rules(target: 30),
      homeworkFull: 60,
    );
    final p = innerOf(r.bodyText)['params'] as Map;
    expect(p['score'], 10); // 原是 int → 新值整数时保持 int
    expect(p['real_score'], 10);
    final d = jsonDecode(p['score_detail'] as String) as Map;
    expect(d['total_score'], 10);
  });

  test('原分>0 时四分项按比例缩放', () {
    final inner = jsonDecode(_androidInner) as List;
    final params = (inner.first as Map)['params'] as Map;
    params['score'] = '18.0';
    params['score_detail'] = jsonEncode({
      'total_score': '18.0',
      'fluency_score': '17.2',
      'accuracy_score': '18.0',
      'integrity_score': '0.0',
      'standard_score': '16.0',
      'category': 'read_chapter',
    });
    final body =
        '{"body":"${base64.encode(utf8.encode(jsonEncode(inner)))}","head":{}}';
    final r = rewriteApiRequestBody(body, rules(target: 30), homeworkFull: 60);
    final d = jsonDecode(
      innerOf(r.bodyText)['params']['score_detail'] as String,
    ) as Map;
    // new/old = 10/18 ≈ 0.5556
    expect(d['total_score'], '10.0');
    expect(d['fluency_score'], '9.6'); // 17.2 × 10/18
    expect(d['integrity_score'], '0.0'); // 0 乘任何比例仍是 0
  });

  test('高级模式：题型精确设分优先于比例', () {
    final r = rewriteApiRequestBody(
      androidBody,
      rules(advanced: true, categoryScores: {'read_chapter': 1.5}),
      homeworkFull: 60,
    );
    final p = innerOf(r.bodyText)['params'] as Map;
    expect(p['score'], '1.5');
  });

  test('未知题型且学习不到满分 → 原样放行并记说明', () {
    final inner = jsonDecode(_androidInner) as List;
    final params = (inner.first as Map)['params'] as Map;
    final sd = jsonDecode(params['score_detail'] as String) as Map;
    sd['category'] = 'mystery_type';
    params['score_detail'] = jsonEncode(sd);
    final body =
        '{"body":"${base64.encode(utf8.encode(jsonEncode(inner)))}","head":{}}';
    final r = rewriteApiRequestBody(body, rules(), homeworkFull: 60);
    expect(r.changed, isFalse);
    expect(r.bodyText, body);
    expect(r.notes.join(), contains('mystery_type'));
  });

  test('没有作业满分时直接给满分（首题场景，避免假满分算错）', () {
    final r = rewriteApiRequestBody(winBody, rules(target: 60));
    final p = innerOf(r.bodyText)['params'] as Map;
    expect(p['score'], 20, reason: '满分未知时按题目满分给分');
  });

  test('改时间：时长换算成提前偏移（UI 填 90 秒 → 提前 90 秒）', () {
    // UI 填时长 90 秒，引擎换算成 timeOffsetSec = -90
    final r = rewriteApiRequestBody(
      androidBody,
      rules(scoreOn: false, timeOn: true, offsetSec: -90),
      now: DateTime(2026, 10, 1, 11, 22, 27),
    );
    expect(r.changed, isTrue);
    final p = innerOf(r.bodyText)['params'] as Map;
    expect(p['client_time'], '2026-10-01 11:20:57');
  });

  test('改时间：时长含天时分秒的组合（1 天 2 时 3 分 4 秒）', () {
    final r = rewriteApiRequestBody(
      androidBody,
      rules(scoreOn: false, timeOn: true, offsetSec: -(93784)),
      now: DateTime(2026, 10, 2, 12, 0, 4),
    );
    final p = innerOf(r.bodyText)['params'] as Map;
    expect(p['client_time'], '2026-10-01 09:57:00');
  });

  test('偏移为零：不改字段（引擎把 -1/未设置转成 timeOn=false）', () {
    final r = rewriteApiRequestBody(
      androidBody,
      rules(scoreOn: false, timeOn: false, offsetSec: 0),
      now: DateTime(2026, 10, 1, 11, 22, 27),
    );
    final p = innerOf(r.bodyText)['params'] as Map;
    expect(p['client_time'], '2026-10-01 11:22:27');
    expect(r.changed, isFalse);
  });

  test('填 0 = 按提交时刻上传：把 client_time 刷成当前时刻', () {
    // 用户填 0 秒 → timeOffsetSec = -0 = 0，规则开启 → 用真实提交时刻改写
    final r = rewriteApiRequestBody(
      androidBody,
      rules(scoreOn: false, timeOn: true, offsetSec: -0),
      now: DateTime(2026, 10, 1, 11, 30, 0),
    );
    final p = innerOf(r.bodyText)['params'] as Map;
    expect(
      p['client_time'],
      '2026-10-01 11:30:00',
      reason: '填 0 时按提交时刻上传，而不是原样放行',
    );
  });

  test('规则全关 → 完全不动', () {
    final r = rewriteApiRequestBody(androidBody, CaptureRules.off);
    expect(r.changed, isFalse);
    expect(r.bodyText, androidBody);
  });

  test('坏数据（非 JSON / 非数组）→ 原样放行', () {
    expect(rewriteApiRequestBody('not json', rules()).changed, isFalse);
    final bad = '{"body":"${base64.encode(utf8.encode('{"a":1}'))}","head":{}}';
    expect(rewriteApiRequestBody(bad, rules()).changed, isFalse);
  });

  test('非 sync-v2 路由的条目不动', () {
    final inner = jsonEncode([
      {
        'r': 'g/set/list',
        'params': {'a': 1},
      },
    ]);
    final body = '{"body":"${base64.encode(utf8.encode(inner))}","head":{}}';
    final r = rewriteApiRequestBody(body, rules());
    expect(r.changed, isFalse);
  });

  test('路由带前导斜杠 / 大小写差异也能识别并改写', () {
    // 双端实际可能写成 "/m/audio/sync-v2"
    for (final route in [
      '/m/audio/sync-v2',
      'M/AUDIO/SYNC-V2',
      'm/audio/sync-v2',
    ]) {
      final inner = jsonDecode(_androidInner) as List;
      ((inner.first as Map)['r'] as String);
      final item = inner.first as Map;
      item['r'] = route;
      final body =
          '{"body":"${base64.encode(utf8.encode(jsonEncode(inner)))}","head":{}}';
      final r = rewriteApiRequestBody(
        body,
        rules(target: 30),
        homeworkFull: 60,
      );
      expect(r.changed, isTrue, reason: '路由 $route 应能命中');
      final p = innerOf(r.bodyText)['params'] as Map;
      expect(p['score'], '10.0', reason: '路由 $route 改写值应为 10.0');
    }
  });

  test('URL 命中但 body 路由不同 → 原样放行并报出真实路由', () {
    final inner = jsonEncode([
      {
        'r': 'm/audio/sync-v2-v3',
        'params': {'a': 1},
      },
    ]);
    final body = '{"body":"${base64.encode(utf8.encode(inner))}","head":{}}';
    final r = rewriteApiRequestBody(body, rules());
    expect(r.changed, isFalse);
    expect(r.notes.first, contains('m/audio/sync-v2-v3'));
  });

  test('学习：sync-v2 响应提取作业满分', () {
    final resp =
        '{"body":"${base64.encode(utf8.encode(jsonEncode([
          {
            'r': kRouteSyncV2,
            'body': {'point': 0.0, 'total_point': 60.0, 'complete': 10},
          },
        ])))}"}';
    final l = learnFromResponseBody('/m/audio/sync-v2?sn=1', resp);
    expect(l, isNotNull);
    expect(l!.homeworkFull, 60.0);
    expect(l.entityMarks, isEmpty);
  });

  test('学习：get-score-detail 响应提取各小题满分', () {
    final resp =
        '{"body":"${base64.encode(utf8.encode(jsonEncode([
          {
            'r': kRouteScoreDetail,
            'body': {
              'score': [
                {'entity_id': '253909', 'total_point': 20.0},
                {'entity_id': '253911', 'total_point': 2.0},
              ],
            },
          },
        ])))}"}';
    final l = learnFromResponseBody('/m/set/get-score-detail', resp);
    expect(l, isNotNull);
    // 作业满分 = 各小题满分之和（供比例分摊用）
    expect(l!.homeworkFull, 22.0);
    expect(l.entityMarks['253909'], 20.0);
    expect(l.entityMarks['253911'], 2.0);
  });

  test('学习：坏响应返回 null 不抛异常', () {
    expect(learnFromResponseBody('/m/audio/sync-v2', 'garbage'), isNull);
    expect(
      learnFromResponseBody('/m/audio/sync-v2', '{"body":"####"}'),
      isNull,
    );
  });
}
