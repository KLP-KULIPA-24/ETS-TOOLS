/// E听说本地数据模型
///
/// 题型注册表设计：所有题型都解析为 [ContentUnit]，
/// 新题型只需在 [EtsStructure.fromName] 与解析逻辑中登记即可自适应。
library;

import 'dart:convert';
import 'dart:io';

/// 题型枚举（structure_type / collector.*）
/// 顺序 = 筛选条展示顺序，按真实考试菜单：模仿朗读 → 角色扮演 → 故事复述
enum EtsStructure {
  read('collector.read', '模仿朗读'),
  threeQ5A('collector.3q5a', '角色扮演'),
  picture('collector.picture', '故事复述'),
  repeatDialogue('collector.repeat_dialogue', '对话跟读'),
  word('collector.word', '单词跟读'),
  unknown('unknown', '未知题型');

  final String key; // collector 名
  final String label; // 中文展示名
  const EtsStructure(this.key, this.label);

  static EtsStructure fromName(String? name) {
    for (final s in EtsStructure.values) {
      if (s.key == name) return s;
    }
    // 兼容未来新题型：包含关键词的模糊匹配
    final n = name ?? '';
    if (n.contains('word')) return EtsStructure.word;
    if (n.contains('3q5a')) return EtsStructure.threeQ5A;
    if (n.contains('picture')) return EtsStructure.picture;
    if (n.contains('repeat')) return EtsStructure.repeatDialogue;
    if (n.contains('read')) return EtsStructure.read;
    return EtsStructure.unknown;
  }
}

/// 标题来源
enum TitleSource { template, adaptive, ai, fallback }

extension TitleSourceExt on TitleSource {
  String get label => switch (this) {
    TitleSource.template => '模板提取',
    TitleSource.adaptive => '自适应匹配',
    TitleSource.ai => 'AI 智能匹配',
    TitleSource.fallback => '默认命名',
  };
}

/// 逐句片段（对话跟读 / 朗读视频时间轴通用）
class SentenceSeg {
  final String seq;
  final String text; // 英文原文
  final String ai; // 官方参考句
  final String translate; // 中文翻译
  final String role; // 角色名
  final double begin; // 开始秒
  final double end; // 结束秒

  const SentenceSeg({
    required this.seq,
    required this.text,
    required this.ai,
    required this.translate,
    required this.role,
    required this.begin,
    required this.end,
  });

  static SentenceSeg fromJson(Map<String, dynamic> j) => SentenceSeg(
    seq: '${j['seq'] ?? ''}',
    text: '${j['text'] ?? ''}',
    ai: '${j['ai'] ?? ''}',
    translate: '${j['translate'] ?? ''}',
    role: '${j['role'] ?? ''}',
    begin: double.tryParse('${j['begintime'] ?? 0}') ?? 0,
    end: double.tryParse('${j['endtime'] ?? 0}') ?? 0,
  );
}

/// 标准答案
class StdAnswer {
  final String value;
  final String ai;
  final String audio; // 相对 material 目录
  const StdAnswer({required this.value, required this.ai, required this.audio});
  static StdAnswer fromJson(Map<String, dynamic> j) => StdAnswer(
    value: '${j['value'] ?? ''}',
    ai: '${j['ai'] ?? ''}',
    audio: '${j['audio'] ?? ''}',
  );
}

/// 一道问答（三问五答等）
class EtsQuestion {
  final String xh; // 序号
  final String ask; // 问题文本
  final String answer; // 参考答案
  final String askAudio;
  final String aswAudio;
  final String sucai; // 素材音频
  final String keywords; // '|' 分隔的评分关键词
  final String role; // a=提问 b=回答
  final String analyze;
  final List<StdAnswer> std;
  final List<String> ref;

  const EtsQuestion({
    required this.xh,
    required this.ask,
    required this.answer,
    required this.askAudio,
    required this.aswAudio,
    required this.sucai,
    required this.keywords,
    required this.role,
    required this.analyze,
    required this.std,
    required this.ref,
  });

  static EtsQuestion fromJson(Map<String, dynamic> j) => EtsQuestion(
    xh: '${j['xh'] ?? ''}',
    ask: '${j['ask'] ?? ''}',
    answer: '${j['answer'] ?? ''}',
    askAudio: '${j['askaudio'] ?? ''}',
    aswAudio: '${j['aswaudio'] ?? ''}',
    sucai: '${j['sucai'] ?? ''}',
    keywords: '${j['keywords'] ?? ''}',
    role: '${j['role'] ?? ''}',
    analyze: '${j['analyze'] ?? ''}',
    std: ((j['std'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => StdAnswer.fromJson(e.cast<String, dynamic>()))
        .toList(),
    ref: ((j['ref'] as List?) ?? []).map((e) => '$e').toList(),
  );

  List<String> get keywordList =>
      keywords.split('|').where((k) => k.trim().isNotEmpty).toList();
}

/// 一份作业内容单元（content_xxx 目录）
class ContentUnit {
  final String dir; // content 目录绝对路径
  final String uid; // 所属账号/批次文件夹名
  final String folderName;
  final EtsStructure structure;
  final Map<String, dynamic> info;
  final DateTime mtime;

  ContentUnit({
    required this.dir,
    required this.uid,
    required this.folderName,
    required this.structure,
    required this.info,
    required this.mtime,
  });

  String get stid =>
      '${info['stid'] ?? folderName.replaceAll(RegExp(r'^content_'), '')}';

  // ---- 各题型字段快捷访问 ----
  String get text => '${info['value'] ?? ''}';
  String get audio => '${info['audio'] ?? ''}';
  String get image => '${info['image'] ?? ''}';
  String get video => '${info['video'] ?? ''}';
  String get translate => '${info['translate'] ?? ''}';
  String get analyze => '${info['analyze'] ?? ''}';
  String get aiText => '${info['ai'] ?? ''}'; // 官方分行版原文
  String get topic => '${info['topic'] ?? ''}'; // picture 标题
  String get readTitle => '${info['read_title'] ?? ''}'; // word 标题
  String get videoTime => '${info['videotime'] ?? ''}'; // 朗读逐句时间轴

  /// 三问五答题列表
  List<EtsQuestion> get questions => ((info['question'] as List?) ?? [])
      .whereType<Map>()
      .map((e) => EtsQuestion.fromJson(e.cast<String, dynamic>()))
      .toList();

  /// 看图说话 std 范文
  List<StdAnswer> get stdAnswers => ((info['std'] as List?) ?? [])
      .whereType<Map>()
      .map((e) => StdAnswer.fromJson(e.cast<String, dynamic>()))
      .toList();

  String get keypoint => '${info['keypoint'] ?? ''}';

  /// 逐句列表（对话跟读 content.json 自带）
  List<SentenceSeg> get sentences => ((info['sublist'] as List?) ?? [])
      .whereType<Map>()
      .map((e) => SentenceSeg.fromJson(e.cast<String, dynamic>()))
      .toList();

  /// 从朗读 videotime 解析逐句: "<00:00><00:05> 句子..."
  List<SentenceSeg> parseVideoTime() {
    final src = videoTime;
    if (src.isEmpty) return const [];
    final re = RegExp(r'<(\d+:\d+(?:\.\d+)?)><(\d+:\d+(?:\.\d+)?)>\s*([^<]*)');
    final out = <SentenceSeg>[];
    var i = 1;
    for (final m in re.allMatches(src)) {
      out.add(
        SentenceSeg(
          seq: '$i',
          text: m.group(3)?.trim() ?? '',
          ai: '',
          translate: '',
          role: '',
          begin: _parseTs(m.group(1)!),
          end: _parseTs(m.group(2)!),
        ),
      );
      i++;
    }
    return out;
  }

  static double _parseTs(String s) {
    final p = s.split(':');
    if (p.length == 2) {
      return (int.tryParse(p[0]) ?? 0) * 60 + (double.tryParse(p[1]) ?? 0);
    }
    return double.tryParse(s) ?? 0;
  }

  /// 自适应标题（第二级策略）：取内容关键词（词边界截断，过滤常见引导词）
  String adaptiveTitle() {
    if (topic.isNotEmpty) return topic;
    if (readTitle.isNotEmpty) return readTitle;
    var t = text
        .replaceAll(RegExp(r'</?[a-zA-Z]+[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (structure == EtsStructure.word && t.isNotEmpty) return t;
    // 模仿朗读：首句完整句做标题（32 字硬截会切出半句如"time for Chin…"）
    if (structure == EtsStructure.read) {
      final m = RegExp(r'^([^.!?]{6,60}[.!?])').firstMatch(t);
      if (m != null) return m.group(1)!.trim();
    }
    // 去掉常见开头引导词
    t = t.replaceFirst(
      RegExp(
        r"^(It's|It is|There (is|are)|This is|The)\s+",
        caseSensitive: false,
      ),
      '',
    );
    if (t.isEmpty) return '作业 $stid';
    // 词边界截断
    const maxLen = 32;
    if (t.length <= maxLen) return t;
    final clip = t.substring(0, maxLen);
    final lastSpace = clip.lastIndexOf(' ');
    return lastSpace > 12 ? '${clip.substring(0, lastSpace)}…' : '$clip…';
  }
}

/// paper.Jason 里的题目
class PaperQuestion {
  final String stid;
  final double score;
  final String title;
  final String audio;
  final String text;
  final List<SentenceSeg> sentences;
  PaperQuestion({
    required this.stid,
    required this.score,
    required this.title,
    required this.audio,
    required this.text,
    required this.sentences,
  });
}

/// paper.Jason 题型分组
class PaperSection {
  final String name; // tx_jc 如"对话跟读"
  final String structure; // cjq_no
  final double score;
  final List<PaperQuestion> items;
  PaperSection({
    required this.name,
    required this.structure,
    required this.score,
    required this.items,
  });
}

/// 一份完整套题（paper.Jason + paper.ctrl + paper.res）
class PaperUnit {
  final String dir;
  final String uid;
  final String tzid;
  final String title; // tz_mc
  final double totalScore; // tz_fs
  final String ctrlComment; // paper.ctrl comment，同步课文标题备用
  final List<PaperSection> sections;
  final DateTime mtime;
  PaperUnit({
    required this.dir,
    required this.uid,
    required this.tzid,
    required this.title,
    required this.totalScore,
    required this.ctrlComment,
    required this.sections,
    required this.mtime,
  });
}

/// ctrl 步骤（考试流程脚本）
class ExamStep {
  final String type; // view.html / file.audio / wait / action.record / user.audio / vari.item
  final String filename;
  final String hint; // 播放录音/准备时间/录音...
  final double playtime; // 时长（秒）
  final String playParams; // 音频区间 "0,4.4"
  final String subId;
  final String dirType;
  final Map<String, String> htmlParams; // classname -> code_id

  const ExamStep({
    required this.type,
    required this.filename,
    required this.hint,
    required this.playtime,
    required this.playParams,
    required this.subId,
    required this.dirType,
    required this.htmlParams,
  });

  /// 播放区间
  double get playFrom {
    final p = playParams.split(',').first.trim();
    return double.tryParse(p) ?? 0;
  }

  double get playTo {
    final parts = playParams.split(',');
    if (parts.length < 2) return -1;
    return double.tryParse(parts[1].trim()) ?? -1;
  }

  static ExamStep fromJson(Map<String, dynamic> j) {
    final params = <String, String>{};
    final jp = (j['model_pc'] as Map?)?['jsparam'] ?? (j['jsparam'] as List?);
    if (jp is List) {
      for (final e in jp.whereType<Map>()) {
        params['${e['classname']}'] = '${e['code_id']}';
      }
    }
    return ExamStep(
      type: '${j['type'] ?? j['filetype'] ?? ''}',
      filename: '${j['filename'] ?? ''}',
      hint: '${j['playhint'] ?? ''}',
      playtime: double.tryParse('${j['playtime'] ?? 0}') ?? 0,
      playParams: '${j['playparams'] ?? ''}',
      subId: '${j['subid'] ?? j['id'] ?? ''}',
      dirType: '${j['dirtype'] ?? ''}',
      htmlParams: params,
    );
  }
}

/// 套题指挥信息（Android 新布局：指挥目录 ctrl.json + res.json）
/// res.json 的 exam_type_list 声明套题各部分的名称/顺序/collector 类型
class SetDirector {
  final String dir;
  final List<SetPart> parts;
  const SetDirector({required this.dir, required this.parts});
}

/// 套题的一个部分（对应一个内容目录）
class SetPart {
  final String name; // res.json exam_type_name，如"模仿朗读"
  final String collect; // exam_type_collect，如 collector.read
  final int order; // exam_type_order
  const SetPart({
    required this.name,
    required this.collect,
    required this.order,
  });
}

/// 作业列表条目（content 或 paper 的统一外壳）
class HomeworkEntry {
  final String uid;
  final String dir;
  final DateTime mtime;
  final ContentUnit? content;
  final PaperUnit? paper;
  final SetDirector? director; // 套题指挥目录
  final String title;
  final TitleSource titleSource;

  /// 归入套题后的部分信息（来自 res.json exam_type_list）
  final String? partName;
  final int? partOrder;

  /// 套题分区标识：Part A / Part B / Part C（组内顺序分配）
  final String? partLabel;

  HomeworkEntry({
    required this.uid,
    required this.dir,
    required this.mtime,
    this.content,
    this.paper,
    this.director,
    required this.title,
    required this.titleSource,
    this.partName,
    this.partOrder,
    this.partLabel,
  });

  HomeworkEntry copyWith({String? partLabel}) => HomeworkEntry(
    uid: uid,
    dir: dir,
    mtime: mtime,
    content: content,
    paper: paper,
    director: director,
    title: title,
    titleSource: titleSource,
    partName: partName,
    partOrder: partOrder,
    partLabel: partLabel ?? this.partLabel,
  );

  EtsStructure get structure =>
      paper != null ? EtsStructure.repeatDialogue : content!.structure;
}

/// 作业分组（"文件夹"收纳）：
/// 一个 uid 目录 = 一份作业（套题），套题的各部分（Part）收进同组；
/// 组名格式：数字 - 标题 - 类别（多类别套题的类别段显示"套题"）
class HomeworkGroup {
  final String uid;
  final EtsStructure structure;
  final String title;
  final List<HomeworkEntry> entries;

  HomeworkGroup({
    required this.uid,
    required this.structure,
    required this.title,
    required this.entries,
  });

  /// 组内是否跨类别（= 一份套题的多个部分）
  bool get isMixed => entries.map((e) => e.structure).toSet().length > 1;

  /// 组标题段（中间那段）：一个文件夹算 1 个，不带数量
  /// 多条同类别用类别名；多条跨类别（套题各部分）显示"套题"
  static String groupTitleOf(EtsStructure structure, List<HomeworkEntry> list) {
    if (list.length == 1) return list.first.title;
    final mixed = list.map((e) => e.structure).toSet().length > 1;
    return mixed ? '套题' : structure.label;
  }

  /// 展示名：数字 - 标题 - 类别
  /// （标题与类别相同或为空时省略中间段；哈希目录名不展示）
  String get displayName {
    final t = title.trim();
    final showUid = uid.length < 16 || !RegExp(r'^[0-9a-f]+$').hasMatch(uid);
    final head = showUid ? '$uid - ' : '';
    final label = isMixed ? '套题' : structure.label;
    if (t.isEmpty || t == label) return '$head$label';
    return '$head$t - $label';
  }
}

/// JSON 读取工具（自动去 BOM）
Map<String, dynamic>? loadJsonMap(String path) {
  try {
    final f = File(path);
    if (!f.existsSync()) return null;
    var s = f.readAsStringSync();
    s = s.replaceFirst('\ufeff', '').trim();
    if (s.isEmpty) return null;
    return jsonDecode(s) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

List<dynamic>? loadJsonList(String path) {
  try {
    final f = File(path);
    if (!f.existsSync()) return null;
    var s = f.readAsStringSync();
    s = s.replaceFirst('\ufeff', '').trim();
    if (s.isEmpty) return null;
    return jsonDecode(s) as List<dynamic>;
  } catch (_) {
    return null;
  }
}
