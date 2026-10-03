import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:e_ets_helper/services/capture_rewrite.dart';
import 'package:e_ets_helper/services/capture_score_rewrite.dart';

/// 响应改写测试（样本 = 2026-10-01 Win 端第二次抓包真实响应）
CaptureRules rules({
  double target = 60,
  bool advanced = false,
  Map<String, double> cat = const {},
}) => CaptureRules(
  scoreOn: true,
  targetScore: target,
  advancedOn: advanced,
  categoryScores: cat,
  timeOn: false,
  timeOffsetSec: 0,
);

/// get-score-detail 真实响应结构（抓包真实字段名）
/// 构造一份与抓包同构的套题：朗读 20 + 情景表达 2×2 + 话题 24 = 满分 48
String _detailItem(String entity, String cat, double total) => jsonEncode({
  'detail_file': 'https://ets60.ets100.com/ugc/evaluate/xml/x.xml',
  'client_time': 1790839556,
  'entity_id': entity,
  'real_score': 0.0,
  'standard_score': 0.0,
  'detail':
      '{"accuracy_score":"0.000000","fluency_score":"0.000000",'
      '"integrity_score":"0.000000","standard_score":"0.000000",'
      '"total_score":0,"real_score":0,"category":"$cat",'
      '"rate_scale":1}',
  'total_point': total,
  'order': 1,
  'timestamp': 1790839556,
});

final String scoreDetailResp = jsonEncode([
  {
    'msg': '成功',
    'code': 0,
    'body': {
      'score': [
        jsonDecode(_detailItem('104814', 'read_chapter', 20.0)),
        jsonDecode(_detailItem('104815', 'simple_expression', 2.0)),
        jsonDecode(_detailItem('104816', 'simple_expression', 2.0)),
        jsonDecode(_detailItem('104817', 'topic', 24.0)),
      ],
      'avg_point': 0,
      'diagnosis': [],
      'dimension_score': {
        'fluency_score': 0.0,
        'integrity_score': 0.0,
        'standard_score': 0.0,
        'accuracy_score': 0.0,
        'manual_modified': false,
        'stress_pronunciation_score': 0.0,
      },
    },
  },
]);

/// g/set/list 真实响应（作业列表：point 总分 / total_point 满分）
final String setListResp = jsonEncode([
  {
    'msg': '成功',
    'code': 0,
    'body': {
      'data': [
        {'set_id': '31897', 'difficulty_rate': 0.67},
      ],
      'score': [
        {
          'first_column_id': '13',
          'avg_point': 0,
          'update': '2026-10-01 15:16:27',
          'set_id': '31897',
          'total_point': 20,
          'complete': 100,
          'point': 0,
        },
      ],
    },
  },
]);

Map bodyOf(String text) =>
    ((jsonDecode(text) as List).first as Map)['body'] as Map;

void main() {
  test('get-score-detail：目标 48/满分 48 → 各题拿满，四分项/汇总/雷达同步', () {
    final r = rewriteScoreResponse(
      scoreDetailResp,
      rules(target: 48),
      route: '/m/set/get-score-detail',
    );
    expect(r.changed, isTrue);
    final body = bodyOf(r.bodyText);
    final list = body['score'] as List;
    final first = list.first as Map;
    expect(first['real_score'], 20.0); // 朗读满 20
    expect((list[3] as Map)['real_score'], 24.0); // 话题满 24
    final d = jsonDecode(first['detail'] as String) as Map;
    expect(d['total_score'], 20);
    expect(d['real_score'], 20);
    // 分项原本是六位小数字符串，必须保持字符串格式
    expect(d['accuracy_score'], '20.000000');
    expect(body['avg_point'], 48.0, reason: '汇总 = 各小题得分和');
    expect(
      (body['dimension_score'] as Map)['fluency_score'],
      12.0,
      reason: '雷达图 = 平均分 48/4',
    );
  });

  test('get-score-detail：目标 24/满分 48 → 各题半区分', () {
    final r = rewriteScoreResponse(
      scoreDetailResp,
      rules(target: 24),
      route: '/m/set/get-score-detail',
    );
    final list = bodyOf(r.bodyText)['score'] as List;
    final first = list.first as Map;
    expect(first['real_score'], 10.0); // 20 的一半
    final d = jsonDecode(first['detail'] as String) as Map;
    expect(d['total_score'], 10);
    expect(d['fluency_score'], '10.000000');
  });

  test('g/set/list：作业列表 point 改写（界面总分）', () {
    // 该套题满分 20：目标 10 → 一半分；目标 60 → 离谱三倍（用户允许超满分）
    final half = rewriteScoreResponse(
      setListResp,
      rules(target: 10),
      route: '/g/set/list',
    );
    expect(half.changed, isTrue);
    final s1 = bodyOf(half.bodyText)['score'] as List;
    expect((s1.first as Map)['point'], 10);
    expect((s1.first as Map)['avg_point'], 10);

    final wild = rewriteScoreResponse(
      setListResp,
      rules(target: 60),
      route: '/g/set/list',
    );
    expect((bodyOf(wild.bodyText)['score'] as List).first, isNotNull);
    expect(
      ((bodyOf(wild.bodyText)['score'] as List).first as Map)['point'],
      60,
    );
  });

  test('规则关闭时响应原样不动', () {
    const off = CaptureRules(
      scoreOn: false,
      targetScore: 0,
      advancedOn: false,
      categoryScores: {},
      timeOn: false,
      timeOffsetSec: 0,
    );
    final r = rewriteScoreResponse(scoreDetailResp, off);
    expect(r.changed, isFalse);
    expect(r.bodyText, scoreDetailResp);
  });

  test('坏 JSON / 非数组 → 原样放行不抛异常', () {
    expect(rewriteScoreResponse('not json', rules()).changed, isFalse);
    expect(rewriteScoreResponse('{"a":1}', rules()).changed, isFalse);
  });

  test('高级模式：题型覆盖优先（read_chapter 精确 17 分）', () {
    final r = rewriteScoreResponse(
      scoreDetailResp,
      rules(advanced: true, cat: {'read_chapter': 17}),
      route: '/m/set/get-score-detail',
    );
    final s = bodyOf(r.bodyText)['score'] as List;
    expect((s.first as Map)['real_score'], 17.0);
  });

  test('学习：明文 get-score-detail 响应能学出作业满分与各小题满分', () {
    final l = learnFromResponseBody('/m/set/get-score-detail', scoreDetailResp);
    expect(l, isNotNull);
    expect(l!.homeworkFull, 48.0, reason: '作业满分=各小题满分之和');
    expect(l.entityMarks['104814'], 20.0);
  });

  test('学习：明文 sync-v2 响应能学出作业满分 total_point', () {
    final resp = jsonEncode([
      {
        'msg': '成功',
        'code': 0,
        'body': {'point': 0.0, 'total_point': 20.0, 'complete': 100},
      },
    ]);
    final l = learnFromResponseBody('/m/audio/sync-v2', resp);
    expect(l, isNotNull);
    expect(l!.homeworkFull, 20.0);
  });
}
