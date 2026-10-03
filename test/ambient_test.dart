import 'dart:convert';

import 'package:e_ets_helper/services/ambient.dart';
import 'package:flutter_test/flutter_test.dart';

/// 氛围模式触发词回归测试。
/// 背景：关键词常量曾漏编一个字母导致命中失败；源码零明文，
/// 肉眼极难发现——这里锁死「拼写正确必须命中」这条回归。
///
/// ⚠️ 本文件也在仓库里：**所有触发词一律以 base64 存放，禁止出现明文**。
final _magic = utf8.decode(base64Decode('6L+b5YWl5byA5Y+R6ICF5qih5byP77yM5oGi5aSN5b2p6JuL'));
final _magicNoComma = utf8.decode(base64Decode('6L+b5YWl5byA5Y+R6ICF5qih5byP5oGi5aSN5b2p6JuL'));
final _kwOnly = utf8.decode(base64Decode('5b2p6JuL55yf5aW9546p'));
// 关键词本体（英文写法 / 中文写法 / 别名）
final _nameEn = utf8.decode(base64Decode('Q3ludGhpYQ=='));
final _nameCn = utf8.decode(base64Decode('6LCt5biM6aKW'));
final _magicFirst = utf8.decode(base64Decode('6L+b5YWl5byA5Y+R6ICF5qih5byP'));
final _typo = utf8.decode(base64Decode('Y3l0aGFuYQ=='));

void main() {
  // 命中会顺带解锁成就并弹 Toast，Toast 要读 navigatorKey，
  // 因此需要先初始化 binding（应用运行时本来就有）
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // 会话级状态，测试间手动复位
    Ambient.I.tinted.value = false;
  });

  group('氛围模式触发词', () {
    test('输入英文关键词命中', () {
      Ambient.I.feed(_nameEn);
      expect(Ambient.I.armed, isTrue);
    });

    test('输入中文关键词命中', () {
      Ambient.I.feed(_nameCn);
      expect(Ambient.I.armed, isTrue);
    });

    test('大小写与前后文不影响命中', () {
      Ambient.I.feed('hey ${_nameEn.toLowerCase()}, 在吗');
      expect(Ambient.I.armed, isTrue);
    });

    test('曾漏编的拼写不再命中（确保编码已修正）', () {
      Ambient.I.feed(_typo);
      expect(Ambient.I.armed, isFalse);
    });

    test('无关文本不命中', () {
      Ambient.I.feed('今天作业写完了吗');
      expect(Ambient.I.armed, isFalse);
    });

    test('命中后置位，重复 feed 保持开启', () {
      Ambient.I.feed(_nameEn);
      Ambient.I.feed('随便说点什么');
      expect(Ambient.I.armed, isTrue);
    });

    test('玩过一轮（fx 弹窗已消费）后关键词失效，暗号恢复资格', () {
      // 语义：完整流程（触发→重启弹修复窗）走完后，关键词就不再响应，
      // 必须输暗号重置 fx 才能再玩。debugSetFxShown 只改内存不写注册表。
      Ambient.I.debugSetFxShown(true);
      Ambient.I.feed(_nameEn);
      Ambient.I.feed(_nameCn);
      expect(Ambient.I.armed, isFalse);
      Ambient.I.debugSetFxShown(false);
      Ambient.I.feed(_nameEn);
      expect(Ambient.I.armed, isTrue);
    });
  });

  group('单一人格（关键词出现即触发 = 固定人格，无平时档）', () {
    setUp(() => Ambient.I.tinted.value = false);

    test('未 armed 时没有人格注入', () {
      expect(Ambient.I.personaFor(_nameEn), isNull);
    });

    test('armed 后：提不提关键词都是同一份人格', () {
      Ambient.I.feed(_nameEn);
      final withName = Ambient.I.personaFor(_nameEn);
      final withoutName = Ambient.I.personaFor('帮我看看这篇朗读短文');
      expect(withName, isNotNull);
      expect(withName, withoutName);
      expect(Ambient.I.persona, withName);
    });

    test('识别支持大小写与中文写法', () {
      Ambient.I.feed(_nameEn);
      expect(Ambient.I.containsName(_nameEn.toLowerCase()), isTrue);
      expect(Ambient.I.containsName('${_nameEn.toUpperCase()}!'), isTrue);
      expect(Ambient.I.containsName(_nameCn), isTrue);
      expect(Ambient.I.containsName('hello world'), isFalse);
    });

    test('本地回复池分档：两池都非空', () {
      Ambient.I.feed(_nameEn);
      final panic = Ambient.I.pickCannedFor(_nameCn);
      final calm = Ambient.I.pickCannedFor('继续练口语');
      expect(panic, isNotEmpty);
      expect(calm, isNotEmpty);
    });
  });

  group('重置暗号', () {
    test('两段关键词同现即命中（内容见 b64）', () {
      expect(Ambient.I.matchMagic(_magic), isTrue);
      expect(Ambient.I.matchMagic(_magicNoComma), isTrue);
    });

    test('只含其一不命中', () {
      expect(Ambient.I.matchMagic(_magicFirst), isFalse);
      expect(Ambient.I.matchMagic(_kwOnly), isFalse);
    });

    test('暗号只重置弹窗资格，不当场解除本次氛围', () {
      // 语义：输暗号后 fx 清零（下次重启可再弹窗、可再触发），
      // 但本次会话的氛围保持到重启为止。若这里失败，说明有人把
      // 暗号改成了当场 unarm，会破坏「重启才还原」的设定。
      Ambient.I.feed(_nameEn);
      expect(Ambient.I.armed, isTrue);
      expect(Ambient.I.matchMagic(_magic), isTrue);
      expect(Ambient.I.armed, isTrue);
    });
  });
}
