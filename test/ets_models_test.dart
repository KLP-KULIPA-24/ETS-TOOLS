import 'package:e_ets_helper/models/ets_models.dart';
import 'package:e_ets_helper/services/ets_data_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ContentUnit', () {
    test('解析三问五答', () {
      final unit = ContentUnit(
        dir: '/tmp/content_259439',
        uid: '253521',
        folderName: 'content_259439',
        structure: EtsStructure.threeQ5A,
        info: {
          'stid': '259439',
          'value': 'W: Hello </br>M: World',
          'question': [
            {
              'xh': '1',
              'ask': '你有信心吗？',
              'answer': 'Yes.',
              'role': 'a',
              'keywords': 'are confident|no limit',
              'std': [
                {'value': 'Yes, I am.', 'ai': '', 'audio': 'a.mp3'},
              ],
            },
          ],
        },
        mtime: DateTime(2026),
      );

      expect(unit.stid, '259439');
      expect(unit.questions, hasLength(1));
      expect(unit.questions.first.std.first.value, 'Yes, I am.');
      expect(unit.questions.first.keywordList, hasLength(2));
      expect(EtsTextTests.paragraphsOf(unit.text), ['W: Hello', 'M: World']);
    });

    test('videotime 解析', () {
      final unit = ContentUnit(
        dir: '/x',
        uid: 'u',
        folderName: 'content_1',
        structure: EtsStructure.read,
        info: {
          'videotime': '<00:00><00:05> First sentence. <00:05><00:10> Second.',
        },
        mtime: DateTime(2026),
      );
      final segs = unit.parseVideoTime();
      expect(segs, hasLength(2));
      expect(segs[0].begin, 0);
      expect(segs[0].end, 5);
      expect(segs[1].text, 'Second.');
    });

    test('题型模糊匹配', () {
      expect(EtsStructure.fromName('collector.3q5a'), EtsStructure.threeQ5A);
      expect(EtsStructure.fromName('collector.new_word_x'), EtsStructure.word);
      expect(
        EtsStructure.fromName('collector.brand_new'),
        EtsStructure.unknown,
      );
    });

    test('ExamStep playparams', () {
      final s = ExamStep(
        type: 'file.audio',
        filename: 'a.mp3',
        hint: '播放录音',
        playtime: 0,
        playParams: '0,4.4',
        subId: 'x',
        dirType: '',
        htmlParams: const {},
      );
      expect(s.playFrom, 0);
      expect(s.playTo, 4.4);
    });
  });

  group('HomeworkGroup 收纳', () {
    HomeworkEntry wordEntry(String uid, String stid, String word) {
      return HomeworkEntry(
        uid: uid,
        dir: '/tmp/content_$stid',
        mtime: DateTime(2026, 1, 1),
        content: ContentUnit(
          dir: '/tmp/content_$stid',
          uid: uid,
          folderName: 'content_$stid',
          structure: EtsStructure.word,
          info: {'stid': stid, 'value': word, 'translate': 'n. 释义'},
          mtime: DateTime(2026, 1, 1),
        ),
        title: word,
        titleSource: TitleSource.adaptive,
      );
    }

    test('同类多条按 文件夹-标题-类别 收纳', () {
      final entries = [
        wordEntry('143165', '165371', 'castle'),
        wordEntry('143165', '165372', 'tower'),
        wordEntry('143165', '165373', 'moat'),
      ];
      final groups = EtsDataService.computeGroups(entries);
      expect(groups, hasLength(1));
      expect(groups.first.displayName, '143165 - 单词跟读');
      expect(groups.first.entries, hasLength(3));
    });

    test('同一 uid 的混合类别合并为一个套题组', () {
      // 现实场景：一份套题（Part A 朗读 + Part B 三问五答）都在同一 uid 目录下，
      // 应收纳成一个套题组，而不是拆成两个条目
      final entries = [
        wordEntry('245105', '253909', 'castle'),
        HomeworkEntry(
          uid: '245105',
          dir: '/tmp/content_253911',
          mtime: DateTime(2026, 1, 2),
          content: ContentUnit(
            dir: '/tmp/content_253911',
            uid: '245105',
            folderName: 'content_253911',
            structure: EtsStructure.threeQ5A,
            info: {'stid': '253911', 'value': 'hello', 'question': []},
            mtime: DateTime(2026, 1, 2),
          ),
          title: 'hello',
          titleSource: TitleSource.adaptive,
        ),
      ];
      final groups = EtsDataService.computeGroups(entries);
      expect(groups, hasLength(1));
      expect(groups.first.entries, hasLength(2));
      expect(groups.first.isMixed, isTrue);
      expect(groups.first.title, '套题');
      expect(groups.first.displayName, '245105 - 套题');
    });
  });
}

class EtsTextTests {
  static List<String> paragraphsOf(String s) {
    // 简单复刻 EtsText.paragraphs 逻辑用于测试断言
    return s
        .replaceAll('</br>', '\n')
        .split('\n')
        .map((e) => e.trim())
        .toList();
  }
}
