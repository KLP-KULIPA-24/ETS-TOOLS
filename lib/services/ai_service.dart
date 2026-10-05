import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/ets_models.dart';
import 'settings_service.dart';

/// AI 动作类型
enum AiAction { analyze, translate, title, adaptive }

extension AiActionExt on AiAction {
  String get id => switch (this) {
    AiAction.analyze => 'analyze',
    AiAction.translate => 'translate',
    AiAction.title => 'title',
    AiAction.adaptive => 'adaptive',
  };
  String get label => switch (this) {
    AiAction.analyze => '智能解析',
    AiAction.translate => '全文翻译',
    AiAction.title => 'AI 标题',
    AiAction.adaptive => 'AI 自适应识别',
  };
}

/// 取消令牌：调用方持有，停止生成 / 离开页面时触发
class AiCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// 用户主动停止生成（不重试、不切换模型）
class AiCancelledException implements Exception {
  @override
  String toString() => '已停止生成';
}

/// OpenAI 兼容 AI 服务（多提供商/多模型，支持思考与多模态）
class AiService {
  static final AiService I = AiService._();

  AiService._();

  Directory? _cacheDir;

  Future<Directory> cacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final docs = await getApplicationDocumentsDirectory();
    _cacheDir = Directory(p.join(docs.path, 'ai_cache'))
      ..createSync(recursive: true);
    return _cacheDir!;
  }

  /// 规范 base：去尾斜杠；已带完整端点路径则原样返回
  String _normBase(String base, String suffix) {
    var b = base.trim();
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    if (b.endsWith(suffix)) return b;
    return '$b$suffix';
  }

  /// 按协议格式拼请求端点
  Uri _endpointUrl(AiProvider provider, String fmt, String modelId) {
    switch (fmt) {
      case 'openai-responses':
        return Uri.parse(_normBase(provider.baseUrl, '/responses'));
      case 'anthropic':
        return Uri.parse(_normBase(provider.baseUrl, '/messages'));
      case 'gemini':
        return Uri.parse(
          '${_normBase(provider.baseUrl, '/models')}'
          '/${modelId.trim()}:streamGenerateContent?alt=sse',
        );
      default:
        return Uri.parse(_normBase(provider.baseUrl, '/chat/completions'));
    }
  }

  Map<String, String> _endpointHeaders(AiProvider provider, String fmt) {
    final key = provider.apiKey.trim();
    switch (fmt) {
      case 'anthropic':
        return {
          'Content-Type': 'application/json',
          'x-api-key': key,
          'anthropic-version': '2023-06-01',
          'Accept': 'text/event-stream',
        };
      case 'gemini':
        return {
          'Content-Type': 'application/json',
          'x-goog-api-key': key,
          'Accept': 'text/event-stream',
        };
      default:
        return {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $key',
          'Accept': 'text/event-stream',
        };
    }
  }

  /// 从 OpenAI 风格 content 数组里取 data URL 图片（mime + base64）
  (String, String)? _dataUrlImage(String url) {
    final m = RegExp(r'^data:image/(\w+);base64,(.+)$').firstMatch(url);
    if (m == null) return null;
    final mime = m.group(1) == 'jpg' ? 'jpeg' : (m.group(1) ?? 'png');
    return (mime, m.group(2) ?? '');
  }

  /// 按协议格式组装请求体。messages 一律是 OpenAI 风格（调用方约定），
  /// 这里做各协议的形状转换；返回 null 的键不要放进请求体。
  Map<String, dynamic> _buildBody({
    required AiProvider provider,
    required AiModel model,
    required String fmt,
    required List<Map<String, dynamic>> messages,
    required double temperature,
    required int maxTokens,
  }) {
    final modelId = model.model.trim();
    // 拆 system：四种协议的 system 都是独立字段（Gemini 的 contents 不收 system）
    var system = '';
    final turns = <Map<String, dynamic>>[];
    for (final m in messages) {
      if ('${m['role']}' == 'system') {
        system = '${m['content']}';
      } else {
        turns.add(m);
      }
    }

    switch (fmt) {
      case 'openai-responses': {
        List<dynamic> convContent(dynamic c) {
          if (c is String) return [{'type': 'input_text', 'text': c}];
          final out = <dynamic>[];
          for (final part in (c as List)) {
            final p = part as Map<String, dynamic>;
            if (p['type'] == 'text') {
              out.add({'type': 'input_text', 'text': p['text']});
            } else if (p['type'] == 'image_url') {
              out.add({
                'type': 'input_image',
                'image_url': (p['image_url'] as Map)['url'],
              });
            }
          }
          return out;
        }

        final body = <String, dynamic>{
          'model': modelId,
          'instructions': system,
          'stream': true,
          'temperature': temperature,
          'max_output_tokens': maxTokens,
          'input': [
            for (final t in turns)
              {'role': t['role'], 'content': convContent(t['content'])},
          ],
        };
        if (model.thinking) {
          const effort = {
            'on': 'medium', 'low': 'low', 'medium': 'medium',
            'high': 'high', 'ultra': 'high', 'max': 'high',
          };
          body['reasoning'] = {
            'effort': effort[model.thinkingLevel] ?? 'medium',
          };
        }
        return body;
      }
      case 'anthropic': {
        List<dynamic> convContent(dynamic c) {
          if (c is String) return [{'type': 'text', 'text': c}];
          final out = <dynamic>[];
          for (final part in (c as List)) {
            final p = part as Map<String, dynamic>;
            if (p['type'] == 'text') {
              out.add({'type': 'text', 'text': p['text']});
            } else if (p['type'] == 'image_url') {
              final img = _dataUrlImage((p['image_url'] as Map)['url'] ?? '');
              if (img != null) {
                out.add({
                  'type': 'image',
                  'source': {
                    'type': 'base64',
                    'media_type': 'image/${img.$1}',
                    'data': img.$2,
                  },
                });
              }
            }
          }
          return out;
        }

        final body = <String, dynamic>{
          'model': modelId,
          'system': system,
          'stream': true,
          'temperature': temperature,
          'max_tokens': maxTokens,
          'messages': [
            for (final t in turns)
              {'role': t['role'], 'content': convContent(t['content'])},
          ],
        };
        if (model.thinking) {
          // 思考预算必须 ≥1024 且小于 max_tokens；开思考时 temperature 固定 1
          final budget = (maxTokens ~/ 2).clamp(1024, 32000);
          body['max_tokens'] = maxTokens + budget;
          body['temperature'] = 1;
          body['thinking'] = {'type': 'enabled', 'budget_tokens': budget};
        }
        return body;
      }
      case 'gemini': {
        List<Map<String, dynamic>> convParts(dynamic c) {
          if (c is String) return [{'text': c}];
          final out = <Map<String, dynamic>>[];
          for (final part in (c as List)) {
            final p = part as Map<String, dynamic>;
            if (p['type'] == 'text') {
              out.add({'text': p['text']});
            } else if (p['type'] == 'image_url') {
              final img = _dataUrlImage((p['image_url'] as Map)['url'] ?? '');
              if (img != null) {
                out.add({
                  'inline_data': {'mime_type': 'image/${img.$1}', 'data': img.$2},
                });
              }
            }
          }
          return out;
        }

        final body = <String, dynamic>{
          'contents': [
            for (final t in turns)
              {
                'role': '${t['role']}' == 'assistant' ? 'model' : 'user',
                'parts': convParts(t['content']),
              },
          ],
          'systemInstruction': {'parts': [{'text': system}]},
          'generationConfig': {
            'temperature': temperature,
            'maxOutputTokens': maxTokens,
          },
        };
        if (model.thinking && model.thinkingLevel == 'on') {
          // -1 = 动态思考；其余档位不注入（各模型预算上限不同，宁缺毋错）
          (body['generationConfig'] as Map)['thinkingConfig'] = {
            'thinkingBudget': -1,
          };
        }
        return body;
      }
      default: {
        final body = <String, dynamic>{
          'model': modelId,
          'messages': messages,
          'stream': true,
          'temperature': temperature,
          'max_tokens': maxTokens,
        };
        // 思考模式：'开' 不注入 effort，改为请求开启思考输出
        // （Qwen3/GLM 网关通用参数；不支持的网关会忽略未知字段）；
        // 低/中/高/超高/最高 注入 reasoning_effort（若接口不支持请关闭思考）
        // Agnes 模型只会有「开」（档位在配置层锁死）
        if (model.thinking) {
          if (model.thinkingLevel == 'on') {
            body['enable_thinking'] = true;
          } else {
            body['reasoning_effort'] = model.thinkingLevel;
          }
        }
        return body;
      }
    }
  }

  /// 解析一条 SSE data。返回 true = 流结束。
  /// onText / onReason 分别接正文与思考增量（正文会再过 think 标签路由）。
  bool _sseData(
    String fmt,
    String data, {
    required void Function(String) onText,
    required void Function(String) onReason,
  }) {
    if (fmt == 'openai' && data == '[DONE]') return true;
    try {
      final j = jsonDecode(data);
      switch (fmt) {
        case 'openai-responses':
          final type = '${j['type']}';
          if (type == 'response.output_text.delta') {
            final d = '${j['delta']}';
            if (d.isNotEmpty) onText(d);
          } else if (type == 'response.reasoning_text.delta' ||
              type == 'response.reasoning_summary_text.delta') {
            final d = '${j['delta']}';
            if (d.isNotEmpty) onReason(d);
          } else if (type == 'response.completed' ||
              type == 'response.failed' ||
              type == 'response.incomplete') {
            return true;
          }
        case 'anthropic':
          final type = '${j['type']}';
          if (type == 'content_block_delta') {
            final d = j['delta'] as Map<String, dynamic>?;
            final dt = '${d?['type']}';
            if (dt == 'text_delta') {
              final t = '${d?['text']}';
              if (t.isNotEmpty) onText(t);
            } else if (dt == 'thinking_delta') {
              final t = '${d?['thinking']}';
              if (t.isNotEmpty) onReason(t);
            }
          } else if (type == 'message_stop') {
            return true;
          }
        case 'gemini':
          final parts =
              j['candidates']?[0]?['content']?['parts'] as List?;
          if (parts != null) {
            for (final part in parts) {
              final p = part as Map<String, dynamic>;
              final t = '${p['text'] ?? ''}';
              if (t.isEmpty) continue;
              if (p['thought'] == true) {
                onReason(t);
              } else {
                onText(t);
              }
            }
          }
          final finish = '${j['candidates']?[0]?['finishReason'] ?? ''}';
          return finish.isNotEmpty && finish != 'null';
        default:
          final delta = j['choices']?[0]?['delta'];
          // 思考内容（DeepSeek 风格 reasoning_content，部分接口叫 reasoning）
          final rc = delta?['reasoning_content'] ?? delta?['reasoning'];
          if (rc is String && rc.isNotEmpty) onReason(rc);
          final deltaContent = delta?['content'];
          if (deltaContent is String && deltaContent.isNotEmpty) {
            onText(deltaContent); // 正文里可能混着 <think> 标签
          }
      }
    } catch (_) {}
    return false;
  }

  /// 非流式整包 JSON 解析（部分网关不回流）。返回 (正文, 思考)。
  (String, String) _parseFull(String fmt, dynamic j) {
    switch (fmt) {
      case 'openai-responses': {
        String text = '${j['output_text'] ?? ''}';
        final reason = StringBuffer();
        final output = j['output'] as List?;
        if (output != null) {
          for (final item in output) {
            final it = item as Map<String, dynamic>;
            if ('${it['type']}' == 'reasoning') {
              for (final s in (it['summary'] as List? ?? const [])) {
                final t = '${(s as Map)['text'] ?? ''}';
                if (t.isNotEmpty) reason.write(t);
              }
              final dt = '${it['content'] ?? ''}';
              if (dt.isNotEmpty && dt != 'null') reason.write(dt);
            } else if (text.isEmpty && '${it['type']}' == 'message') {
              for (final c in (it['content'] as List? ?? const [])) {
                final cm = c as Map<String, dynamic>;
                if ('${cm['type']}' == 'output_text') {
                  text += '${cm['text'] ?? ''}';
                }
              }
            }
          }
        }
        return (text, reason.toString());
      }
      case 'anthropic': {
        final content = StringBuffer();
        final reason = StringBuffer();
        for (final b in (j['content'] as List? ?? const [])) {
          final bm = b as Map<String, dynamic>;
          if ('${bm['type']}' == 'text') {
            content.write('${bm['text'] ?? ''}');
          } else if ('${bm['type']}' == 'thinking') {
            reason.write('${bm['thinking'] ?? ''}');
          }
        }
        return (content.toString(), reason.toString());
      }
      case 'gemini': {
        final content = StringBuffer();
        final reason = StringBuffer();
        final parts =
            j['candidates']?[0]?['content']?['parts'] as List?;
        for (final part in (parts ?? const [])) {
          final p = part as Map<String, dynamic>;
          final t = '${p['text'] ?? ''}';
          if (t.isEmpty) continue;
          if (p['thought'] == true) {
            reason.write(t);
          } else {
            content.write(t);
          }
        }
        return (content.toString(), reason.toString());
      }
      default: {
        final msg = j['choices']?[0]?['message'];
        final rc = '${msg?['reasoning_content'] ?? msg?['reasoning'] ?? ''}';
        var content = '${msg?['content'] ?? ''}';
        return (content, rc);
      }
    }
  }

  /// 组装消息：纯文本或（多模态）图文数组
  List<Map<String, dynamic>> _buildMessages({
    required String system,
    required String user,
    List<String> imagePaths = const [],
  }) {
    final s = SettingsService.I;
    final model = s.currentModel;
    if (model != null && model.multimodal && imagePaths.isNotEmpty) {
      final content = <Map<String, dynamic>>[
        {'type': 'text', 'text': user},
      ];
      for (final path in imagePaths) {
        final f = File(path);
        if (!f.existsSync()) continue;
        final b64 = base64Encode(f.readAsBytesSync());
        final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
        final mime = ext == 'jpg' ? 'jpeg' : (ext.isEmpty ? 'png' : ext);
        content.add({
          'type': 'image_url',
          'image_url': {'url': 'data:image/$mime;base64,$b64'},
        });
      }
      return [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': content},
      ];
    }
    return [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ];
  }

  /// 流式对话。onDelta 回调增量文本，返回完整文本。
  /// [firstTokenTimeout] 内没有任何输出则视为失败（用于故障切换）。
  /// [maxTokens] 不传时用模型设定的最大输出，仍未设定则 4096。
  Future<String> chatStream({
    required List<Map<String, dynamic>> messages,
    ValueChanged<String>? onDelta,
    double temperature = 0.4,
    int? maxTokens,
    Duration firstTokenTimeout = const Duration(seconds: 10),
  }) async {
    final s = SettingsService.I;
    final model = s.currentModel;
    final provider = model == null ? null : s.providerOf(model);
    if (model == null || provider == null || !s.aiReady) {
      throw Exception('未选择可用模型：请到设置添加模型并填写 API Key');
    }
    return _chatOnce(
      provider: provider,
      model: model,
      messages: messages,
      onDelta: onDelta,
      temperature: temperature,
      maxTokens: maxTokens ?? model.maxOutput ?? 4096,
      firstTokenTimeout: firstTokenTimeout,
    );
  }

  // 速率限制：固定窗口——从窗口内第一次调用起算 60s，到期次数整体重置回满
  static DateTime? _windowStart;
  static int _windowCount = 0;

  static void _rollWindow() {
    if (_windowStart != null &&
        DateTime.now().difference(_windowStart!).inSeconds >= 60) {
      _windowStart = null;
      _windowCount = 0;
    }
  }

  /// 当前窗口剩余次数；-1 = 未限速
  static int get rateWindowRemaining {
    final perMin = SettingsService.I.aiRatePerMin;
    if (perMin <= 0) return -1;
    _rollWindow();
    return (perMin - _windowCount).clamp(0, perMin);
  }

  /// 距次数重置（回满）的秒数；null = 当前没有进行中的窗口
  static int? windowResetSec() {
    if (SettingsService.I.aiRatePerMin <= 0) return null;
    _rollWindow();
    if (_windowStart == null) return null;
    final left =
        const Duration(minutes: 1) - DateTime.now().difference(_windowStart!);
    return left.inSeconds.clamp(0, 60);
  }

  Future<void> _rateLimit({
    void Function(Duration wait, int remaining)? onWait,
    int? perMin,
  }) async {
    final limit = perMin ?? 10;
    if (limit <= 0) return;
    while (true) {
      _rollWindow();
      _windowStart ??= DateTime.now(); // 窗口从第一次调用起算
      if (_windowCount < limit) {
        _windowCount++;
        return;
      }
      // 等窗口重置（次数回满）
      final wait =
          const Duration(minutes: 1) -
          DateTime.now().difference(_windowStart!) +
          const Duration(milliseconds: 200);
      final real = wait < const Duration(milliseconds: 200)
          ? const Duration(milliseconds: 200)
          : wait;
      onWait?.call(real, limit);
      await Future.delayed(real);
    }
  }

  /// 自动故障切换：按用户排列的模型优先级依次尝试，
  /// 出错或 [firstTokenTimeout] 内无输出自动切换下一个；
  /// 每个模型失败后按设置的次数自动重试。
  /// [forceModel] 非 null 时只调用该模型（不进故障切换链，不碰其他模型）；
  /// [onAttemptStart] 在每次尝试开始时触发（调用方清空上一轮残缺流式文本）；
  /// [onStatus] 上报重试/切换状态（调用方用独立状态行展示，不混入正文）；
  /// [onRateWait] 触发限速排队时回调（等待时长 + 窗口剩余次数）；
  /// [cancel] 触发后立即断开连接，不重试不切换，抛 [AiCancelledException]。
  /// [maxTokens] 不传时用各模型设定的最大输出，仍未设定则 4096。
  Future<(String, AiModel)> chatWithFailover({
    required List<Map<String, dynamic>> messages,
    ValueChanged<String>? onDelta,
    ValueChanged<String>? onReason, // 思考内容增量（reasoning_content）
    void Function()? onAttemptStart,
    ValueChanged<String>? onStatus,
    void Function(Duration wait, int remaining)? onRateWait,
    AiCancelToken? cancel,
    AiModel? forceModel,
    double temperature = 0.4,
    int? maxTokens,
  }) async {
    final s = SettingsService.I;
    final chain = forceModel != null ? [forceModel] : s.failoverChain;
    if (chain.isEmpty) {
      throw Exception('没有可用模型：请到设置添加模型并填写对应提供商的 API Key');
    }
    if (cancel?.isCancelled ?? false) throw AiCancelledException();
    final errors = <String>[];
    for (final model in chain) {
      final provider = s.providerOf(model);
      if (provider == null) continue;
      // 每模型独立策略：模型设置优先，未设置跟随全局默认
      final retries = model.retries.clamp(0, 5);
      final buf = StringBuffer();
      Object? lastError;
      for (var attempt = 0; attempt <= retries; attempt++) {
        if (cancel?.isCancelled ?? false) throw AiCancelledException();
        if (attempt > 0) {
          await Future.delayed(const Duration(milliseconds: 800));
          if (cancel?.isCancelled ?? false) throw AiCancelledException();
          onStatus?.call('自动重试 ${attempt + 1}/$retries…');
        }
        buf.clear();
        onAttemptStart?.call();
        try {
          await _rateLimit(onWait: onRateWait, perMin: model.ratePerMin);
          final reasoning = StringBuffer();
          final out = await _chatOnce(
            provider: provider,
            model: model,
            messages: messages,
            onDelta: (d) {
              buf.write(d);
              onDelta?.call(d);
            },
            onReason: (d) {
              reasoning.write(d);
              onReason?.call(d);
            },
            cancel: cancel,
            temperature: temperature,
            maxTokens: maxTokens ?? model.maxOutput ?? 4096,
            // 10s 无首 token 即判失败：20s × 5 次重试会让界面"卡加载"100 秒
            firstTokenTimeout: const Duration(seconds: 10),
          );
          return (out, model);
        } on AiCancelledException {
          rethrow; // 用户停止：不重试、不切换
        } catch (e) {
          lastError = e;
        }
      }
      errors.add('${model.name}: ${lastError ?? '未知错误'}');
      onStatus?.call('${model.name} 失败，已切换到下一个模型…');
    }
    throw Exception('所有模型均失败：\n${errors.join('\n')}');
  }

  Future<String> _chatOnce({
    required AiProvider provider,
    required AiModel model,
    required List<Map<String, dynamic>> messages,
    ValueChanged<String>? onDelta,
    ValueChanged<String>? onReason,
    AiCancelToken? cancel,
    required double temperature,
    required int maxTokens,
    required Duration firstTokenTimeout,
  }) async {
    final fmt = kApiFormats.contains(provider.apiFormat)
        ? provider.apiFormat
        : 'openai';
    final req = http.Request(
      'POST',
      _endpointUrl(provider, fmt, model.model),
    );
    req.headers.addAll(_endpointHeaders(provider, fmt));
    req.body = jsonEncode(
      _buildBody(
        provider: provider,
        model: model,
        fmt: fmt,
        messages: messages,
        temperature: temperature,
        maxTokens: maxTokens,
      ),
    );

    if (cancel?.isCancelled ?? false) throw AiCancelledException();

    // 首 token 超时：规定时间内没有任何输出 → 抛出以触发故障切换
    var firstReceived = false;
    Completer<void>? timeoutSignal;
    Timer? firstTimer;
    void wrappedDelta(String d) {
      if (!firstReceived) {
        firstReceived = true;
        firstTimer?.cancel();
        timeoutSignal?.complete();
      }
      onDelta?.call(d);
    }

    final resp = await req.send().timeout(const Duration(seconds: 60));
    if (resp.statusCode != 200) {
      final body2 = await resp.stream.bytesToString();
      throw Exception('AI 接口错误 ${resp.statusCode}: $body2');
    }
    timeoutSignal = Completer<void>();
    firstTimer = Timer(firstTokenTimeout, () {
      if (!firstReceived && !timeoutSignal!.isCompleted) {
        timeoutSignal.complete();
      }
    });

    // 部分网关/接口不返回流式响应：整体读取后一次性回调
    final contentType = resp.headers['content-type'] ?? '';
    if (contentType.contains('application/json')) {
      final body2 = await resp.stream.bytesToString();
      final j = jsonDecode(body2);
      var (content, rc) = _parseFull(fmt, j);
      // 正文里可能混着 <think> 块：剥离进思考通道
      final m = RegExp(r'^\s*<think>([\s\S]*?)(?:</think>|$)')
          .firstMatch(content);
      if (m != null) {
        if ((m.group(1) ?? '').isNotEmpty) rc += m.group(1)!;
        content = content.substring(m.end);
      }
      if (rc.isNotEmpty) onReason?.call(rc);
      if (content.isNotEmpty) wrappedDelta(content);
      firstTimer.cancel();
      return content;
    }

    // SSE 流式解析
    final buf = StringBuffer();
    final completer = Completer<String>();
    StreamSubscription? sub;
    Timer? idleTimer;
    Timer? cancelPoll;

    // 断流看门狗：首 token 后，相邻内容间隔超时视为断流（避免永久挂起）
    const idleTimeout = Duration(seconds: 60);
    void resetIdle() {
      idleTimer?.cancel();
      idleTimer = Timer(idleTimeout, () {
        if (!completer.isCompleted) {
          completer.completeError(
            TimeoutException(
              '输出中断：${idleTimeout.inSeconds}s 内无新内容',
              idleTimeout,
            ),
          );
        }
      });
    }

    // 思考输出：也算有效输出（喂活首 token 计时与看门狗，长思考不被误杀）
    void reasonOut(String d) {
      if (!firstReceived) {
        firstReceived = true;
        firstTimer?.cancel();
        timeoutSignal?.complete();
      }
      onReason?.call(d);
      resetIdle();
    }

    // <think> 标签路由：部分模型把思考包在正文流里（Qwen/GLM 风格）
    var inThink = false;
    final tagBuf = StringBuffer();
    int partialTagLen(String s, String tag) {
      for (var k = tag.length - 1; k >= 1; k--) {
        if (s.endsWith(tag.substring(0, k))) return k;
      }
      return 0;
    }

    void routeContent(String d) {
      tagBuf.write(d);
      var s = tagBuf.toString();
      tagBuf.clear();
      while (s.isNotEmpty) {
        if (!inThink) {
          final i = s.indexOf('<think>');
          if (i < 0) {
            // 行尾可能是被截断的 "<think>" 前缀，先扣留
            final hold = partialTagLen(s, '<think>');
            if (hold > 0) {
              tagBuf.write(s.substring(s.length - hold));
              s = s.substring(0, s.length - hold);
            }
            if (s.isNotEmpty) {
              buf.write(s);
              wrappedDelta(s);
            }
            break;
          }
          if (i > 0) {
            buf.write(s.substring(0, i));
            wrappedDelta(s.substring(0, i));
          }
          s = s.substring(i + 7);
          inThink = true;
        } else {
          final i = s.indexOf('</think>');
          if (i < 0) {
            final hold = partialTagLen(s, '</think>');
            if (hold > 0) {
              tagBuf.write(s.substring(s.length - hold));
              s = s.substring(0, s.length - hold);
            }
            if (s.isNotEmpty) reasonOut(s);
            break;
          }
          if (i > 0) reasonOut(s.substring(0, i));
          s = s.substring(i + 8);
          inThink = false;
        }
      }
    }

    // 流结束时把扣留的尾巴按当前状态归位（无闭合标签的思考也算思考）
    void flushTags() {
      final s = tagBuf.toString();
      if (s.isEmpty) return;
      tagBuf.clear();
      if (inThink) {
        reasonOut(s);
      } else {
        buf.write(s);
        wrappedDelta(s);
      }
    }

    void finish() {
      firstTimer?.cancel();
      cancelPoll?.cancel();
      idleTimer?.cancel();
    }

    // 取消轮询：令牌触发后立刻断开连接（流空闲时 listen 回调不会触发，需独立轮询）
    if (cancel != null) {
      cancelPoll = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (cancel.isCancelled && !completer.isCompleted) {
          completer.completeError(AiCancelledException());
        }
      });
    }

    sub = resp.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (cancel?.isCancelled ?? false) {
              if (!completer.isCompleted) {
                completer.completeError(AiCancelledException());
              }
              return;
            }
            line = line.trim();
            if (!line.startsWith('data:')) return;
            final data = line.substring(5).trim();
            final done = _sseData(
              fmt,
              data,
              onText: routeContent,
              onReason: reasonOut,
            );
            if (data.isNotEmpty && !done) resetIdle();
            if (done && !completer.isCompleted) {
              flushTags();
              completer.complete(buf.toString());
            }
          },
          onDone: () {
            flushTags();
            finish();
            if (!completer.isCompleted) completer.complete(buf.toString());
          },
          onError: (e) {
            flushTags();
            finish();
            if (!completer.isCompleted) completer.completeError(e);
          },
        );

    // 与首 token 超时竞速：超时且无输出 → 抛错触发故障切换
    final timeoutFuture = timeoutSignal.future.then<String>((_) {
      if (!firstReceived) {
        throw TimeoutException(
          '模型 ${model.name} 在 ${firstTokenTimeout.inSeconds}s 内无输出',
        );
      }
      return Completer<String>().future; // 已有输出：等真实结果
    });
    try {
      return await Future.any<String>([completer.future, timeoutFuture]);
    } finally {
      // 无论超时/取消/出错都掐断底层连接，杜绝旧流把迟到文字串进新输出
      finish();
      await sub.cancel();
    }
  }

  Future<File> _cacheFile(String stid, AiAction action) async {
    final d = await cacheDir();
    return File(p.join(d.path, '${stid}_${action.id}.md'));
  }

  Future<String?> getCached(String stid, AiAction action) async {
    final f = await _cacheFile(stid, action);
    if (f.existsSync()) return f.readAsStringSync();
    return null;
  }

  Future<void> saveCache(String stid, AiAction action, String text) async {
    final f = await _cacheFile(stid, action);
    await f.writeAsString(text);
  }

  Future<void> clearCache(String stid, AiAction action) async {
    final f = await _cacheFile(stid, action);
    if (f.existsSync()) await f.delete();
  }

  /// 测试连接（当前模型）
  Future<String> testConnection() async {
    final r = await chatStream(
      messages: const [
        {'role': 'user', 'content': '请回复：连接成功'},
      ],
      maxTokens: 32,
    );
    return r.trim();
  }

  static String _clip(String s, int n) => s.length > n ? s.substring(0, n) : s;

  /// 用户考试信息（学段/地区）注入：AI 必须按此考纲口径
  static String get _examCtx {
    final s = SettingsService.I;
    final parts = [
      if (s.grade.isNotEmpty) '当前学段：${s.grade}',
      if (s.region.isNotEmpty) '所在地区：${s.region}',
    ];
    return parts.isEmpty ? '' : '\n${parts.join('，')}。请严格按该学段与地区考纲作答。';
  }

  // ---- 各动作 prompt ----

  List<Map<String, dynamic>> _analyzePrompt(ContentUnit c) {
    final sb = StringBuffer();
    sb.writeln('# 题目数据');
    sb.writeln('- 题型: ${c.structure.label} (${c.structure.key})');
    if (c.text.isNotEmpty) {
      sb.writeln('- 原文/材料:\n${c.text.replaceAll('</br>', '\n')}');
    }
    if (c.translate.isNotEmpty) sb.writeln('- 官方翻译: ${c.translate}');
    if (c.keypoint.isNotEmpty) sb.writeln('- 官方要点: ${c.keypoint}');
    final qs = c.questions;
    if (qs.isNotEmpty) {
      for (final q in qs) {
        sb.writeln('## 第${q.xh}题 (${q.role == 'a' ? '三问-提问' : '五答-回答'})');
        sb.writeln('- 问题: ${q.ask}');
        if (q.answer.isNotEmpty) sb.writeln('- 参考答案: ${q.answer}');
        if (q.std.isNotEmpty) {
          sb.writeln('- 标准答案选项: ${q.std.map((e) => e.value).join(' / ')}');
        }
        if (q.keywordList.isNotEmpty) {
          sb.writeln('- 评分关键词: ${q.keywordList.join('；')}');
        }
      }
    }
    return _buildMessages(
      system:
          '你是高中/初中英语听说考试（E听说）资深辅导老师。用中文、Markdown 输出，条理清晰，重点突出，面向备考学生。$_examCtx',
      user: '''请对下面的英语听说题目做全面解析，输出包含：
1. **材料大意**（2-3 句概括）
2. **逐题解析**（每题：题意、答案要点、易错点、答题技巧）
3. **重点词汇短语**（英文 + 中文释义，表格）
4. **备考建议**（针对该题型的口诀/技巧）

${sb.toString()}''',
    );
  }

  List<Map<String, dynamic>> _translatePrompt(ContentUnit c) {
    return _buildMessages(
      system: '你是专业英中翻译。输出 Markdown，保持原文分段。$_examCtx',
      user:
          '请将下面的英语材料翻译成通顺的中文（逐段对照：先英文段，再中文翻译）：\n\n${c.text.replaceAll('</br>', '\n')}',
    );
  }

  List<Map<String, dynamic>> _titlePrompt(ContentUnit c) {
    return _buildMessages(
      system: '你是帮助整理作业标题的助手。只输出一个简短中文标题（不超过 20 字），不要其他内容。$_examCtx',
      user:
          '根据以下内容给这份英语听说作业起一个标题（可含教材单元信息则更好）：\n\n${_clip(c.text.replaceAll('</br>', '\n'), 1200)}',
    );
  }

  List<Map<String, dynamic>> _adaptivePrompt(ContentUnit c) {
    final raw = const JsonEncoder.withIndent('  ').convert(c.info);
    return _buildMessages(
      system: '你是 E听说数据格式专家。用中文 Markdown 输出。$_examCtx',
      user: '''这是一份 E听说作业的 JSON 数据（题型标记为 ${c.structure.key}，可能是新题型）。请自适应识别并输出：
1. **识别结果**：推断这是什么题型、题干是什么、要求学生做什么
2. **题目与答案**：把所有题目和对应的答案/范文整理成清晰的列表
3. **其他有用信息**：评分关键词、音频说明等

JSON 数据：
$raw''',
    );
  }

  /// 执行动作（带缓存），onDelta 流式回调
  Future<String> run(
    ContentUnit c,
    AiAction action, {
    ValueChanged<String>? onDelta,
    bool force = false,
  }) async {
    if (!force) {
      final cached = await getCached(c.stid, action);
      if (cached != null) return cached;
    }
    await clearCache(c.stid, action);
    final List<Map<String, dynamic>> msgs;
    switch (action) {
      case AiAction.analyze:
        msgs = _analyzePrompt(c);
      case AiAction.translate:
        msgs = _translatePrompt(c);
      case AiAction.title:
        msgs = _titlePrompt(c);
      case AiAction.adaptive:
        msgs = _adaptivePrompt(c);
    }
    final out = await chatWithFailover(
      messages: msgs,
      onDelta: onDelta,
    ).then((r) => r.$1);
    await saveCache(c.stid, action, out);
    return out;
  }
}
