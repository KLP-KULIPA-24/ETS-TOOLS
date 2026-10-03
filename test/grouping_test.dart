import 'dart:io';

import 'package:e_ets_helper/services/ets_data_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 套题分组：一个 uid 目录 = 一份套题，Part A/B/C 各一个 content_* 目录，
/// 应合并为一个组而不是拆成 3 个条目。
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ets_group_test');
    final uid = Directory('${root.path}${Platform.pathSeparator}617734');
    uid.createSync(recursive: true);
    void part(String name, String type, String title) {
      final d = Directory('${uid.path}${Platform.pathSeparator}$name')
        ..createSync();
      File('${d.path}${Platform.pathSeparator}content.json').writeAsStringSync(
        '{"structure_type":"$type","info":{"stid":"$name","title":"$title"}}',
      );
    }

    part('content_665428', 'collector.read', '朗读短文｜the Terracotta Army');
    part('content_665429', 'collector.3q5a', '三问五答｜school life');
    part('content_665430', 'collector.picture', '看图说话｜a park');
    // 另一份独立作业（不同 uid）
    final uid2 = Directory('${root.path}${Platform.pathSeparator}999999')
      ..createSync();
    final d2 = Directory('${uid2.path}${Platform.pathSeparator}content_1')
      ..createSync();
    File('${d2.path}${Platform.pathSeparator}content.json').writeAsStringSync(
      '{"structure_type":"collector.read","info":{"stid":"1","title":"独立朗读"}}',
    );
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('同一 uid 的三个部分合并为一个套题组', () {
    final entries = EtsDataService.scanRootForTest(root.path);
    expect(entries, hasLength(4), reason: '扫描仍应发现全部 4 个 content 目录');

    final groups = EtsDataService.computeGroups(entries);
    expect(groups, hasLength(2), reason: '3 个部分应合并成 1 个组');

    final suit = groups.firstWhere((g) => g.entries.length == 3);
    expect(suit.uid, '617734');
    expect(suit.isMixed, isTrue, reason: '三个部分跨类别');
    expect(suit.title, '套题');
    expect(suit.displayName, contains('617734'));
    expect(suit.displayName, contains('套题'));
    expect(
      suit.displayName.contains('朗读短文'),
      isFalse,
      reason: '混合套题不应只显示第一个部分的类别',
    );

    final single = groups.firstWhere((g) => g.entries.length == 1);
    expect(single.isMixed, isFalse);
    expect(single.displayName, startsWith('999999 - '));
    expect(single.displayName.contains('套题'), isFalse, reason: '单条作业不应显示套题字样');
  });
}
