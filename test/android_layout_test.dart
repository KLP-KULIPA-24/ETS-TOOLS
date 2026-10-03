import 'dart:io';

import 'package:e_ets_helper/models/ets_models.dart';
import 'package:e_ets_helper/services/ets_data_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 集成测试：使用 Mumu 共享文件夹拷贝出来的真实安卓数据
/// （若该目录不存在则跳过）
/// 真实形态：resource/ 下 4 个哈希目录 = 1 个指挥（ctrl+res）+ 3 个内容
/// （collector.read / 3q5a / picture）= 一份套题（模仿朗读+角色扮演+故事复述）
void main() {
  const androidCopy = r'C:\Users\Admin\Documents\MuMu共享文件夹\Download\resource';

  test('安卓新布局：四目录合为一份套题（模仿朗读/角色扮演/故事复述）', () {
    final root = Directory(androidCopy);
    if (!root.existsSync()) {
      markTestSkipped('未找到安卓数据拷贝目录');
      return;
    }
    final entries = EtsDataService.scanRootForTest(androidCopy);
    expect(entries, isNotEmpty);

    // 1) 三种题型都被识别
    for (final s in [
      EtsStructure.read,
      EtsStructure.threeQ5A,
      EtsStructure.picture,
    ]) {
      expect(
        entries.any((e) => e.structure == s),
        isTrue,
        reason: '应识别 ${s.key}',
      );
    }

    // 2) 套题合并：3 个内容目录 + 1 个指挥目录 = 1 组、3 部分
    final groups = EtsDataService.computeGroups(entries);
    expect(
      groups.length,
      1,
      reason: '指挥目录应吸收内容目录，合为 1 份套题，实际 ${groups.length} 组',
    );
    final g = groups.first;
    expect(g.entries.length, 3, reason: '套题含 3 个部分');
    expect(g.isMixed, isTrue);

    // 部分顺序 = res.json exam_type_order：模仿朗读→角色扮演→故事复述
    expect(g.entries.map((e) => e.partName).toList(), ['模仿朗读', '角色扮演', '故事复述']);
    expect(g.entries.map((e) => e.structure).toList(), [
      EtsStructure.read,
      EtsStructure.threeQ5A,
      EtsStructure.picture,
    ]);

    // 展示名不应含哈希目录名
    expect(
      g.displayName.contains(RegExp(r'[0-9a-f]{32}')),
      isFalse,
      reason: '展示名不应包含哈希目录名: ${g.displayName}',
    );

    // 3) 模仿朗读：原版考试视频 + 逐句时间轴
    final read = g.entries.firstWhere((e) => e.structure == EtsStructure.read);
    expect(read.content!.video, 'content.mp4');
    expect(
      read.content!.parseVideoTime(),
      isNotEmpty,
      reason: 'videotime 应解析出逐句时间轴',
    );

    // 4) 角色扮演：三问五答 8 问
    final role = g.entries.firstWhere(
      (e) => e.structure == EtsStructure.threeQ5A,
    );
    expect(role.content!.questions.length, greaterThanOrEqualTo(8));

    // 5) 故事复述：3 份独立标准范文
    final story = g.entries.firstWhere(
      (e) => e.structure == EtsStructure.picture,
    );
    expect(story.content!.stdAnswers.length, 3, reason: '三份标准复述范文应分别保留');
  });
}
