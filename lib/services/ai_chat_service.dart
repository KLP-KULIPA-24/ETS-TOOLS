import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'settings_service.dart';

/// 一条对话消息
class ChatMsg {
  final String role; // user / assistant
  final String text;
  final List<String> imagePaths; // 本地图片路径（多模态用）
  final bool isError; // 错误提示气泡：界面可见、随历史落盘，但不参与后续请求上下文
  final bool stopped; // 被打断的半截回复：可"继续生成"
  final String? thinking; // 思考内容（reasoning）
  final double? thinkSecs; // 思考用时
  final int? tokens; // 生成 token 数（本地估算）
  final double? tokRate; // 生成速率 tokens/s
  final double? secs; // 生成用时

  ChatMsg({
    required this.role,
    required this.text,
    this.imagePaths = const [],
    this.isError = false,
    this.stopped = false,
    this.thinking,
    this.thinkSecs,
    this.tokens,
    this.tokRate,
    this.secs,
  });

  ChatMsg withStats({
    required int tokens,
    required double tokRate,
    required double secs,
  }) => ChatMsg(
    role: role,
    text: text,
    imagePaths: imagePaths,
    isError: isError,
    stopped: stopped,
    thinking: thinking,
    thinkSecs: thinkSecs,
    tokens: tokens,
    tokRate: tokRate,
    secs: secs,
  );

  Map<String, dynamic> toJson() => {
    'role': role,
    'text': text,
    'images': imagePaths,
    if (isError) 'error': true,
    if (stopped) 'stopped': true,
    if (thinking != null && thinking!.isNotEmpty) 'thinking': thinking,
    if (thinkSecs != null) 'thinkSecs': thinkSecs,
    if (tokens != null) 'tokens': tokens,
    if (tokRate != null) 'tokRate': tokRate,
    if (secs != null) 'secs': secs,
  };

  static ChatMsg fromJson(Map<String, dynamic> j) {
    var text = '${j['text'] ?? ''}';
    var stopped = j['stopped'] == true;
    // 兼容旧版：打断标记写在正文后缀里
    if (!stopped && text.endsWith('（已停止）')) {
      stopped = true;
      text = text.substring(0, text.length - '（已停止）'.length).trimRight();
    }
    if (text == '（已停止，未生成内容）') {
      stopped = true;
      text = '';
    }
    return ChatMsg(
      role: '${j['role'] ?? 'user'}',
      text: text,
      imagePaths: ((j['images'] as List?) ?? const [])
          .map((e) => '$e')
          .toList(),
      isError: j['error'] == true,
      stopped: stopped,
      thinking: j['thinking'] == null ? null : '${j['thinking']}',
      thinkSecs: (j['thinkSecs'] as num?)?.toDouble(),
      tokens: (j['tokens'] as num?)?.toInt(),
      tokRate: (j['tokRate'] as num?)?.toDouble(),
      secs: (j['secs'] as num?)?.toDouble(),
    );
  }
}

/// 会话元数据（列表用）
class ConvoMeta {
  final String id;
  final String title;
  final int updatedAt; // epoch ms
  final int count; // 消息条数

  ConvoMeta({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.count,
  });
}

/// AI 实时对话：多会话 + 历史持久化
/// - 'global' 作用域：多会话（列表 + 子界面），存 `ai_chat/global/<id>.json` + `_index.json`
/// - 其他 key（如 stid）：单文件按作业隔离，存 `ai_chat/<key>.json`
class AiChatService {
  static final AiChatService I = AiChatService._();

  AiChatService._();

  Directory? _dir;

  Future<Directory> _dirOf() async {
    if (_dir != null) return _dir!;
    final docs = await getApplicationDocumentsDirectory();
    _dir = Directory(p.join(docs.path, 'ai_chat'))..createSync(recursive: true);
    return _dir!;
  }

  // ---- 思考内容净化：过滤可能出现的内部指令/设定字样 ----
  // 首项为特定人格的专用词，按惯例走 b64（源码不出现可关联明文）
  static final String _markQuirk = utf8.decode(base64Decode('5Y+j55mW'));
  static const _reasonMarks = [
    'reply style',
    '风格要求',
    '内部内容',
    '人设',
    '系统提示',
    '提示词',
    '设定',
  ];

  static String cleanReason(String s) {
    if (s.isEmpty) return s;
    final kept = s.split('\n').where((line) {
      final low = line.toLowerCase();
      if (low.contains(_markQuirk)) return false;
      return !_reasonMarks.any((m) => low.contains(m));
    }).toList();
    return kept.join('\n').trim();
  }

  // ---- token 估算（接口多不回 usage，本地估算并标"约"）----
  // 东亚字符 ≈ 1 字/token，其他 ≈ 4 字符/token
  static int estimateTokens(String s) {
    if (s.isEmpty) return 0;
    var cjk = 0, other = 0;
    for (final r in s.runes) {
      if (r >= 0x2E80) {
        cjk++;
      } else {
        other++;
      }
    }
    return cjk + (other / 4).ceil();
  }

  // ---- 作用域目录 ----
  Future<Directory> _scopeDir(String scope) async {
    final d = await _dirOf();
    final sd = Directory(p.join(d.path, scope));
    if (!sd.existsSync()) sd.createSync(recursive: true);
    return sd;
  }

  File _convoFile(Directory sd, String id) => File(p.join(sd.path, '$id.json'));
  File _indexFile(Directory sd) => File(p.join(sd.path, '_index.json'));

  /// 旧版单文件迁移：ai_chat/global.json → global 会话
  Future<void> _migrateLegacyGlobal() async {
    final d = await _dirOf();
    final legacy = File(p.join(d.path, 'global.json'));
    if (!legacy.existsSync()) return;
    try {
      final msgs = (jsonDecode(legacy.readAsStringSync()) as List)
          .whereType<Map>()
          .map((e) => ChatMsg.fromJson(e.cast<String, dynamic>()))
          .toList();
      final id = 'c${legacy.statSync().modified.millisecondsSinceEpoch}';
      await saveConvo('global', id: id, msgs: msgs, title: '历史对话');
      legacy.delete();
    } catch (_) {}
  }

  List<ConvoMeta> _readIndex(Directory sd) {
    final f = _indexFile(sd);
    if (!f.existsSync()) return [];
    try {
      return ((jsonDecode(f.readAsStringSync()) as List).whereType<Map>())
          .map(
            (e) => ConvoMeta(
              id: '${e['id'] ?? ''}',
              title: '${e['title'] ?? ''}',
              updatedAt: (e['updatedAt'] as num?)?.toInt() ?? 0,
              count: (e['count'] as num?)?.toInt() ?? 0,
            ),
          )
          .where((e) => e.id.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _writeIndex(Directory sd, List<ConvoMeta> list) {
    _indexFile(sd).writeAsStringSync(
      jsonEncode([
        for (final m in list)
          {
            'id': m.id,
            'title': m.title,
            'updatedAt': m.updatedAt,
            'count': m.count,
          },
      ]),
    );
  }

  /// 会话列表（按更新时间倒序）；global 首次调用触发旧文件迁移
  Future<List<ConvoMeta>> listConvos(String scope) async {
    try {
      final sd = await _scopeDir(scope);
      if (scope == 'global') await _migrateLegacyGlobal();
      final list = _readIndex(sd)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<List<ChatMsg>> loadConvo(String scope, String id) async {
    try {
      final sd = await _scopeDir(scope);
      final f = _convoFile(sd, id);
      if (!f.existsSync()) return [];
      return (jsonDecode(f.readAsStringSync()) as List)
          .whereType<Map>()
          .map((e) => ChatMsg.fromJson(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 保存会话：写消息文件并更新索引（新会话用 [title] 或自动取首条用户消息作标题）
  Future<void> saveConvo(
    String scope, {
    required String id,
    required List<ChatMsg> msgs,
    String? title,
  }) async {
    try {
      final sd = await _scopeDir(scope);
      _convoFile(
        sd,
        id,
      ).writeAsStringSync(jsonEncode(msgs.map((e) => e.toJson()).toList()));
      final index = _readIndex(sd);
      final t = (title != null && title.isNotEmpty)
          ? title
          : index
                .firstWhere(
                  (e) => e.id == id,
                  orElse: () =>
                      ConvoMeta(id: id, title: '', updatedAt: 0, count: 0),
                )
                .title;
      final meta = ConvoMeta(
        id: id,
        title: t.isNotEmpty ? t : _deriveTitle(msgs),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        count: msgs.length,
      );
      final i = index.indexWhere((e) => e.id == id);
      if (i >= 0) {
        index[i] = meta;
      } else {
        index.add(meta);
      }
      _writeIndex(sd, index);
    } catch (_) {}
  }

  Future<void> deleteConvo(String scope, String id) async {
    try {
      final sd = await _scopeDir(scope);
      final f = _convoFile(sd, id);
      if (f.existsSync()) await f.delete();
      final index = _readIndex(sd)..removeWhere((e) => e.id == id);
      _writeIndex(sd, index);
    } catch (_) {}
  }

  String _deriveTitle(List<ChatMsg> msgs) {
    final first = msgs.firstWhere(
      (m) => m.role == 'user',
      orElse: () => msgs.firstOrNull ?? ChatMsg(role: 'user', text: ''),
    );
    var t = first.text.replaceAll('\n', ' ').trim();
    if (t.isEmpty) t = '图片对话';
    if (t.length > 18) t = t.substring(0, 18);
    return t;
  }

  // ---- 旧接口：非 global key（作业内对话）沿用单文件 ----

  Future<List<ChatMsg>> load(String key) async {
    try {
      // _fileOf 依赖 _dir，必须先初始化，否则启动后首次加载崩溃 → 静默丢历史
      await _dirOf();
      if (key == 'global') return [];
      final f = _legacyFile(key);
      if (!f.existsSync()) return [];
      final list = (jsonDecode(f.readAsStringSync()) as List)
          .whereType<Map>()
          .map((e) => ChatMsg.fromJson(e.cast<String, dynamic>()))
          .toList();
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> save(String key, List<ChatMsg> msgs) async {
    try {
      await _dirOf();
      _legacyFile(key)
          .writeAsStringSync(jsonEncode(msgs.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> clear(String key) async {
    try {
      await _dirOf();
      final f = _legacyFile(key);
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }

  File _legacyFile(String key) => File(p.join(_dir!.path, '$key.json'));

  /// 构造多轮请求消息（含图片多模态、系统人设与作业上下文）。
  /// [maxContext] / [maxOutput] 来自当前模型设定：给定 maxContext 时按估算
  /// tokens 从最新往旧裁剪历史，给输出留出空间。
  List<Map<String, dynamic>> buildRequest({
    required List<ChatMsg> history,
    String? contextTitle,
    String? contextText,
    String? persona,
    int? maxContext,
    int? maxOutput,
  }) {
    final sys = StringBuffer();
    sys.write(
      '你是 E听说助手 内置 AI 助手，专注初中/高中英语听说考试辅导。'
      '回答用中文，简洁准确，必要时使用 Markdown。',
    );
    // 用户在设置里选定的学段/地区必须随请求下发，避免 AI 弄错考纲
    final s = SettingsService.I;
    final exam = [
      if (s.grade.isNotEmpty) '当前学段：${s.grade}',
      if (s.region.isNotEmpty) '所在地区：${s.region}',
    ];
    if (exam.isNotEmpty) {
      sys.write(
        '\n${exam.join('，')}。请严格按该学段与地区考纲作答'
        '（题型、难度、评分口径均按此）。',
      );
    }
    if (persona != null && persona.isNotEmpty) {
      sys.write('\n$persona');
    }
    if (contextTitle != null && contextTitle.isNotEmpty) {
      sys.write('\n当前用户正在查看作业：《$contextTitle》');
    }
    if (contextText != null && contextText.trim().isNotEmpty) {
      sys.write(
        '\n作业内容如下（供参考回答）：\n${contextText.length > 4000 ? contextText.substring(0, 4000) : contextText}',
      );
    }
    // 上下文裁剪：预算 = maxContext - 输出预留 - 系统提示余量
    var kept = history.where((m) => !m.isError).toList();
    if (maxContext != null && maxContext > 0) {
      final budget = maxContext - (maxOutput ?? 4096) - 256;
      var used =
          estimateTokens(sys.toString()) +
          (contextText == null ? 0 : estimateTokens(contextText));
      final keep = <ChatMsg>[];
      for (final m in kept.reversed) {
        final t =
            estimateTokens(m.text) +
            (m.imagePaths.isEmpty ? 0 : 1000 * m.imagePaths.length);
        if (used + t > budget && keep.isNotEmpty) break;
        used += t;
        keep.add(m);
      }
      kept = keep.reversed.toList();
    }
    return [
      {'role': 'system', 'content': sys.toString()},
      for (final m in kept) ..._encode(m),
    ];
  }

  List<Map<String, dynamic>> _encode(ChatMsg m) {
    if (m.role == 'assistant') {
      return [
        {'role': 'assistant', 'content': m.text},
      ];
    }
    if (m.imagePaths.isNotEmpty) {
      final content = <Map<String, dynamic>>[
        {'type': 'text', 'text': m.text},
      ];
      for (final path in m.imagePaths) {
        try {
          final f = File(path);
          if (!f.existsSync()) continue;
          final b64 = base64Encode(f.readAsBytesSync());
          final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
          final mime = ext == 'jpg' ? 'jpeg' : (ext.isEmpty ? 'png' : ext);
          content.add({
            'type': 'image_url',
            'image_url': {'url': 'data:image/$mime;base64,$b64'},
          });
        } catch (_) {}
      }
      return [
        {'role': 'user', 'content': content},
      ];
    }
    return [
      {'role': 'user', 'content': m.text},
    ];
  }
}
