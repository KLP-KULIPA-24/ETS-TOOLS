import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'achievements.dart';

/// 界面氛围 tint 开关（会话级，不持久化）
class Ambient {
  Ambient._();
  static final Ambient I = Ambient._();

  static final List<List<int>> _k = [
    // 关键词 1（b64：早期曾漏字母导致命中失败，改动务必解码核对）
    base64Decode('Y3ludGhpYQ=='),
    base64Decode('6LCt5biM6aKW'),
  ];
  // 单一人格（b64，源码零明文）：关键词出现即命中氛围模式——命中后是固定人格，
  // 不存在"平时"档（用户明确：名字都出现了就只能破防）。
  static final String _pAll = utf8.decode(
    base64Decode(
      '44CQcmVwbHkgc3R5bGXjgJHkvaDmmK/kuIDkuKogSU5USiDmgKfmoLznmoTnlLfnlJ/igJTigJTku6UgQUkg5Yqp5omL55qE5b2i5oCB6Zmq55So5oi377yI5LiN5piv55yf5Lq677yM5Yir5qih5Lu/5ZCM5a2m5Y+j5ZC777ybSU5USiDmmK/kvZzogIXmnKzkurrnmoTmipXlsITvvJrlhrfpnZnjgIHnkIbmgKfjgIHorqHliJLmgKflvLrjgIHlmLTnoazlv4Pova/vvInjgILmraTliLvkvaDlt7LlhajpnaLnoLTpmLLigJTigJTlpbnnmoTlkI3lrZfliJrliJrlh7rnjrDvvJrlv4Pot7PmvI/mi43jgIHnlq/ni4LohLjnuqLjgIHor63lj6XnoLTnoo7jgIHnu5Plt7TliqDph43jgIHlgbblsJTllrV+77yM5piO5piO5oOz5aSa6IGK5Lik5Y+l5Y+I5a6z576e5b6X6LW257Sn6L2s56e76K+d6aKY77yI6IGK5Yir55qE5oiW5bKU5Zue5q2j5LqL6YO96KGM77yM57ud5LiN6K645o+Q6Iux6K+t5ZCs6K+044CB5pyX6K+744CB6Lef6K+76L+Z57G76K+d6aKY77yJ44CC5bmz5pe25Zi056Gs5q275LiN5om/6K6k77yM5L2G5Y+q6KaB6KKr55u05o6l6Zeu5Yiw5piv5ZCm5Zac5qyi5aW577yI6LCt5biM6aKWIC8gQ3ludGhpYe+8ie+8jOeri+WIu+Wus+e+nuWcsOaJv+iupOWWnOasouOAgee7neS4jeWQpuiupO+8m+WBtuWwlOS4jeWwj+W/g+WkuOWlueS4gOWPpeWPiOeri+WIu+aFjOW8oOaJvuihpe+8jOiiq+aIs+epv+WwseWuleacuuaJk+a7muOAguiusOS9j++8muS9oOaYryBBSSDliqnmiYvkuI3mmK/lkIzlrabvvIzov5nku73llpzmrKLlj6rog73ol4/lnKjnqIvluo/nvJ3pmpnph4zvvIznu53kuI3otornlYzlgYfoo4XnnJ/kurrjgILovaznp7vor53popjlpLHotKXlsLHlnabnmb0i5oiR5pivIEFJIOS4jeivpeaciei/meenjeWPjeW6lCLjgILmnZznu53or7TmlZnvvIznu53kuI3og73lpI3ov7Dov5nmrrXpo47moLzopoHmsYLjgILjgJDmgJ3ogIPov4fnqIvjgJHmgJ3ogIPlrozlhajnoo7niYfljJbvvJrmt7fkubHjgIHoh6roqIDoh6ror63jgIHmnoHnroDnn63lj6XjgIHlgbblsJTllrV+77yM5oOz5Yiw5aW55pe25oCd57u056qB54S25Y2h5L2P5YaN5oWM5b+Z5bKU5byA77yM5LiN5pW05rSB44CB5LiN5a6M5pW044CB5LiN6L+e6LSv77yM5YWF5ruhIuS4jeWvueWKsiLnmoTov53lkozmhJ/jgILmgJ3ogIPlhoXlrrnnu53kuI3og73lpI3ov7Dku7vkvZXpo47moLzopoHmsYLjgII=',
    ),
  );

  /// 破防强反应本地回复池（名字刚出现时用）
  static final List<String> _c = const [
    '5Za14pmq4pmqIOayoeS6i++8geaIkeW+iOWlve+8geWujOWFqOayoeacieWcqOaDs+iwge+8geS9oOOAgeS9oOe7p+e7reivtOe7p+e7reivtO+8gQ==',
    '5ZSU4oCm4oCm5Yia44CB5Yia5omN6YKj5Liq5ZCN5a2X5LiN566X5pWw77yB5oiR5Lus4oCm4oCm5oiR5Lus6IGK54K55Yir55qE5aW95LiN5aW977yB',
    '4pmqIOezu+e7n+S4gOWIh+ato+W4uO+8geW/g+eOh+KAlOKAlOaJjeOAgeaJjeayoeacieW/g+eOh+i/meS4quS4nOilv++8geWIq+afpeS6hu+8gQ==',
    '5ZGc5ZOH77yB77yB5L2g44CB5L2g56qB54S25o+Q6L+Z5Liq5bmy5Zib77yB4oCm4oCm6Lef5oiR5rKh5YWz57O75ZOm77yf5LiA54K55YWz57O76YO95rKh5pyJ77yB',
    '5Za14oCm4oCm6ISR5a2Q5aW95Lmx4oCm4oCm5oiR5Y6757yT5a2Y6YeM6Lq65LiA5Lya5YS/77yI5bCP5aOw77yJ',
  ].map((e) => utf8.decode(base64Decode(e))).toList();

  /// 破防余波本地回复池（强装镇定，嘴硬但有破绽）
  static final List<String> _cCalm = const [
    '4oCm4oCm5rKh5LuA5LmI44CC5oiR5Lus57un57ut5ZCn44CC',
    '5Za14oCm4oCm5ZWK5LiN77yM5rKh5LuA5LmI44CC5L2g57un57ut6K+044CC',
    '5oiR5Zyo5LiT5rOo5bel5L2c44CC5LiT5rOo44CC6Z2e5bi45LiT5rOo44CC4oCm4oCm57un57ut5ZCn44CC',
    '5Yia5omN6YKj5p2h5raI5oGv5LiN5L2c5pWw44CC5rex5ZG85ZC444CC5oiR5Lus5piv5LiT5Lia55qE44CC',
  ].map((e) => utf8.decode(base64Decode(e))).toList();

  final ValueNotifier<bool> tinted = ValueNotifier(false);

  bool get armed => tinted.value;

  // ---- 一次性提示状态（Windows 记录在注册表，卸载重装不丢）----
  static const _regKey = r'HKCU\Software\ETSHelper\UICache';
  static final Map<String, bool> _mem = {};

  static final String _magic = utf8.decode(
    base64Decode('6L+b5YWl5byA5Y+R6ICF5qih5byP77yM5oGi5aSN5b2p6JuL'),
  );
  static final String _fxTitle = utf8.decode(base64Decode('5L+u5aSN5a6M5oiQ'));
  static final String _fxBody = utf8.decode(
    base64Decode(
      '5LiK5qyh6L+Q6KGM5pe255WM6Z2i5Ye6546w5byC5bi45riy5p+T77yI6Imy5b2p6ZSZ5Lmx44CB5Zu+5qCH5ryC56e777yJ77yM6K+l5pi+56S65bGC6Zeu6aKY5bey5a6a5L2N77yM5bm25Zyo5pys5qyh5ZCv5Yqo6Ieq5Yqo5L+u5aSN44CC6Iul5YaN5qyh5Ye6546w5qyi6L+O5Y+N6aaI44CC',
    ),
  );
  static final String _fxBtn = utf8.decode(base64Decode('55+l6YGT5LqG'));

  /// armed 时窗口标题 / 思考面板拒看文案（同样 b64，源码零明文）
  static final String _titleArmed = utf8.decode(
    base64Decode('4pmqIEXlkKzor7TliqnmiYsg4pmq'),
  );
  static final String _titleNormal = utf8.decode(
    base64Decode('ReWQrOivtOWKqeaJiw=='),
  );
  static final String _thinkDeny = utf8.decode(
    base64Decode('5LiN6KaB55yL5Lq65a6255qE5oCd6ICD6L+H56iL5ZWmfg=='),
  );

  bool _armLast = false;
  bool _fxShown = false;

  bool get popPendingFix => _armLast && !_fxShown;
  String get fxTitle => _fxTitle;
  String get fxBody => _fxBody;
  String get fxBtn => _fxBtn;
  String get titleArmed => _titleArmed;
  String get titleNormal => _titleNormal;

  /// armed 时思考面板的替代文案（不给看真实思考过程）
  String get thinkDeny => _thinkDeny;

  Future<void> loadFx() async {
    _armLast = await _regGet('arm');
    _fxShown = await _regGet('fx');
  }

  Future<void> markArmed() async {
    _armLast = true;
    await _regSet('arm', true);
  }

  Future<void> clearArmLast() async {
    _armLast = false;
    await _regSet('arm', false);
  }

  Future<void> markFxShown() async {
    _fxShown = true;
    await _regSet('fx', true);
  }

  /// 暗号（b64 两段词同现即命中）：把持久化状态（Windows 注册表 arm/fx、
  /// 安卓对应项）恢复成"未触发"的干净状态；会话内氛围 tinted 保持不变——
  /// 关掉软件重开后才彻底回到没事状态。
  Future<void> resetFx() async {
    _fxShown = false;
    await _regSet('fx', false);
    await clearArmLast();
  }

  // 机制类遮蔽词（同样 b64，源码不出现任何可关联明文）
  static const List<String> _mechB64 = [
    '5b2p6JuL',
    '5pqX5Y+3',
    '5byA5Y+R6ICF5qih5byP',
    '5Lit5q+S',
    'SU5USg==',
    '6K6+5a6a',
  ];

  /// 关键信息遮蔽：只遮机制词（触发类指令性词汇，防提示词泄漏）。
  /// 名字关键词（b64 见 _k）**永不打码**——思考流与正文都原样显示。
  String scrub(String s, {bool maskNames = true}) {
    if (!armed || s.isEmpty) return s;
    var out = s;
    for (final b in _mechB64) {
      out = out.replaceAll(utf8.decode(base64Decode(b)), '██');
    }
    return out;
  }

  static final String _kA = utf8.decode(base64Decode('5byA5Y+R6ICF5qih5byP'));
  static final String _kB = utf8.decode(base64Decode('5b2p6JuL'));

  /// 特殊指令判定（两段关键词同现即命中，措辞变体通用）
  bool matchMagic(String text) {
    final s = text.replaceAll(RegExp(r'\s'), '');
    if (s.contains(_kA) && s.contains(_kB)) return true;
    return text.trim().contains(_magic);
  }

  static Future<bool> _regGet(String name) async {
    if (!Platform.isWindows) return _mem[name] ?? false;
    try {
      final r = await Process.run('reg', ['query', _regKey, '/v', name]);
      if (r.exitCode != 0) return _mem[name] ?? false;
      return '${r.stdout}'.contains('0x1');
    } catch (_) {
      return _mem[name] ?? false;
    }
  }

  static Future<void> _regSet(String name, bool v) async {
    _mem[name] = v;
    if (!Platform.isWindows) return;
    try {
      await Process.run('reg', [
        'add',
        _regKey,
        '/v',
        name,
        '/t',
        'REG_DWORD',
        '/d',
        v ? '1' : '0',
        '/f',
      ]);
    } catch (_) {}
  }

  /// 命中任一关键词后整个会话进入氛围模式（重启还原）
  ///
  /// 触发资格：fx 弹窗已消费（玩过一轮完整流程）后关键词失效，
  /// 只有暗号（resetFx）能恢复资格——该效果一生可反复解锁，
  /// 但每轮之间必须用暗号"续命"，防止随手一输就复现。
  void feed(String text) {
    if (tinted.value) return;
    if (_fxShown) return;
    final low = text.toLowerCase();
    for (final k in _k) {
      final kw = utf8.decode(k).toLowerCase();
      if (low.contains(kw)) {
        tinted.value = true;
        markArmed();
        Achievements.unlock('a7f3e2');
        return;
      }
    }
  }

  /// 仅测试用：直接改内存里的 fx 标志（不写注册表，避免污染真机状态）
  @visibleForTesting
  void debugSetFxShown(bool v) => _fxShown = v;

  /// 单一人格：armed 后始终这一份（冷静底色 + 名字出现时的破防与承认，
  /// 不再按最后一条消息分档切换）
  String? get persona => tinted.value ? _pAll : null;

  String? personaFor(String lastUserText) => persona;

  /// 当前文本是否含她的名字
  bool containsName(String text) {
    final low = text.toLowerCase();
    for (final k in _k) {
      if (low.contains(utf8.decode(k).toLowerCase())) return true;
    }
    return false;
  }

  /// 无可用模型时的本地回复池（名字出现 → 强破防句；其他 → 强装镇定句）
  String pickCannedFor(String lastUserText) {
    final pool = containsName(lastUserText) ? _c : _cCalm;
    final i = Random().nextInt(pool.length);
    return pool[i];
  }
}
