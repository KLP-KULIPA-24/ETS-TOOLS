import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'capture_ca.dart';
import 'capture_log.dart';
import 'capture_rewrite.dart';
import 'capture_score_rewrite.dart';
import 'capture_system.dart';
import 'settings_service.dart';

/// 构建标识：每次改引擎都手动抬一位，方便确认"跑的是哪个包"
const String kEngineBuild = 'r8-响应改写+首题拿满';

/// 引擎运行状态（修改页状态行 / 状态卡展示）
@immutable
class CaptureStatus {
  final bool running;
  final int port;
  final String error;

  /// 命中 sync-v2 的请求数
  final int intercepted;

  /// 完成改写的请求数
  final int rewritten;

  /// 命中但未改写的请求数
  final int passed;

  /// 最近一条说明（转发失败等传输层问题）
  final String lastNote;

  /// 最近一次改写相关说明（独立字段，不被转发失败覆盖）
  final String lastRewrite;

  /// 最近事件（诊断用：MITM / sync-v2 命中与结果），最新在前
  final List<String> events;

  const CaptureStatus({
    required this.running,
    required this.port,
    this.error = '',
    this.intercepted = 0,
    this.rewritten = 0,
    this.passed = 0,
    this.lastNote = '',
    this.lastRewrite = '',
    this.events = const [],
  });

  CaptureStatus copyWith({
    bool? running,
    int? port,
    String? error,
    int? intercepted,
    int? rewritten,
    int? passed,
    String? lastNote,
    String? lastRewrite,
    List<String>? events,
  }) => CaptureStatus(
    running: running ?? this.running,
    port: port ?? this.port,
    error: error ?? this.error,
    intercepted: intercepted ?? this.intercepted,
    rewritten: rewritten ?? this.rewritten,
    passed: passed ?? this.passed,
    lastNote: lastNote ?? this.lastNote,
    lastRewrite: lastRewrite ?? this.lastRewrite,
    events: events ?? this.events,
  );
}

/// 本地 HTTPS 代理拦截引擎。
///
/// 工作方式：监听 127.0.0.1:port 作为 HTTP 代理。
/// - CONNECT 到 [kMitmHost]:443 → 用自签 CA 动态证书 MITM，
///   命中 `/m/audio/sync-v2` 的请求按设置改写后转发；
/// - 其余一切流量（含其他站点、OSS 上传）原样盲转发；
/// - 任何环节出错：能放行就放行，绝不弄挂作业。
class CaptureEngine {
  static final CaptureEngine I = CaptureEngine._();

  CaptureEngine._();

  final ca = CaptureCa();
  final ValueNotifier<CaptureStatus> status = ValueNotifier(
    const CaptureStatus(running: false, port: 8888),
  );

  ServerSocket? _server;
  SecureServerSocket? _mitmServer;

  /// 满分知识库（安卓请求不带满分，从响应学习）：resource_id → 作业满分
  final Map<String, double> _homeworkFull = {};

  /// resource_id|entity_id → 小题满分
  final Map<String, double> _entityMarks = {};
  File? _knowledgeFile;
  Timer? _persistDebounce;

  /// 代理看门狗：系统代理指向引擎、但引擎没在监听时自动还原（否则整机断网）
  Timer? _watchdog;

  /// 主程序启动时调用：加载知识库、恢复残留代理、后台预热 CA、启动看门狗
  Future<void> init() async {
    await CaptureLog.I.init();
    unawaited(CaptureLog.I.w('日志目录：${CaptureLog.hintPath}'));
    try {
      final dir = await getApplicationSupportDirectory();
      _knowledgeFile = File(p.join(dir.path, 'capture', 'knowledge.json'));
      _loadKnowledge();
    } catch (_) {}
    unawaited(CaptureSystem.recoverLeftover());
    unawaited(_warmCa());
    _watchdog ??= Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_checkProxyHealth());
    });
  }

  /// 若系统代理仍指向本机某端口，但引擎没在该端口监听 → 自动还原系统代理
  Future<void> _checkProxyHealth() async {
    try {
      final cur = await CaptureSystem.currentProxyPort();
      if (cur == null) return; // 系统代理不是我们
      final s = status.value;
      if (s.running && s.port == cur) return;
      await CaptureSystem.proxyRestore();
      _update((st) => st.copyWith(error: '系统代理指向 $cur 端口但引擎未监听，已自动还原（避免断网）'));
    } catch (_) {}
  }

  Future<void> _warmCa() async {
    try {
      final dir = await getApplicationSupportDirectory();
      await ca.ensureReady(dir);
    } catch (e) {
      debugPrint('CaptureCa warm: $e');
    }
  }

  // ---------------- 启动 / 停止 ----------------

  Future<String?> start(int port) async {
    if (status.value.running) return null;
    try {
      // init() 已后台预热 CA 时跳过 path_provider 依赖（也免重复 RSA）
      if (!ca.ready) {
        final dir = await getApplicationSupportDirectory();
        await ca.ensureReady(dir);
      }
      _mitmServer = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        ca.securityContext,
      );
      _mitmServer!.listen(
        _handleMitmClient,
        onError: (Object _) {},
        cancelOnError: false,
      );
      _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      _server!.listen(
        _handleClient,
        onError: (Object _) {},
        cancelOnError: false,
      );
      _update(
        (s) => s.copyWith(
          running: true,
          port: _server!.port,
          error: '',
          rewritten: 0,
          passed: 0,
          lastRewrite: '',
        ),
      );
      unawaited(
        CaptureLog.I.w(
          '引擎已启动 端口=${_server!.port} '
          'MITM=${ca.ready ? "就绪" : "未就绪"} 证书=${ca.caCertPath}',
        ),
      );
      unawaited(CaptureLog.I.w('构建标识 BUILD=$kEngineBuild'));
      return null;
    } catch (e) {
      await _teardown();
      _update((s) => s.copyWith(running: false, error: '启动失败：$e'));
      unawaited(CaptureLog.I.w('引擎启动失败：$e'));
      return '$e';
    }
  }

  Future<void> stop() async {
    await _teardown();
    _update((s) => s.copyWith(running: false));
  }

  Future<void> _teardown() async {
    try {
      await _server?.close();
    } catch (_) {}
    _server = null;
    try {
      await _mitmServer?.close();
    } catch (_) {}
    _mitmServer = null;
  }

  void _update(CaptureStatus Function(CaptureStatus) f) {
    status.value = f(status.value);
  }

  CaptureRules get _rules {
    final s = SettingsService.I;
    final target = double.tryParse(s.captureScore.trim()) ?? 0;
    final hasOverride =
        s.captureAdvancedOn && s.captureCategoryScoreMap.isNotEmpty;
    return CaptureRules(
      // 目标分无效且没有题型覆盖时，改分视为关闭（避免把成绩改坏成 0）
      scoreOn: s.captureScoreOn && (target > 0 || hasOverride),
      targetScore: target,
      advancedOn: s.captureAdvancedOn,
      categoryScores: s.captureCategoryScoreMap,
      // -1 = 全空（不改）；>=0 = 主动提前的秒数（0 即按提交时刻上传）
      timeOn: s.captureTimeOn && s.captureTimeSec >= 0,
      // UI 填的是时长（天/时/分/秒）= 完成时刻提前量，后台换算成负偏移
      timeOffsetSec: s.captureTimeSec < 0 ? 0 : -s.captureTimeSec,
    );
  }

  // ---------------- 代理入口 ----------------

  Future<void> _handleClient(Socket client) async {
    final buf = _SockBuf(client);
    try {
      final head = await buf.readUntil(_crlfcrlf, 16 * 1024);
      if (head == null) return _drop(client);
      final headText = utf8.decode(head, allowMalformed: true);
      final reqLine = headText
          .substring(0, headText.length - 4)
          .split('\r\n')
          .first;
      final parts = reqLine.split(' ');
      if (parts.length < 2) return _drop(client);

      if (parts[0].toUpperCase() == 'CONNECT') {
        final idx = parts[1].lastIndexOf(':');
        final host = (idx > 0 ? parts[1].substring(0, idx) : parts[1])
            .toLowerCase()
            .replaceAll(RegExp(r'\.$'), '');
        final port = idx > 0
            ? int.tryParse(parts[1].substring(idx + 1)) ?? 443
            : 443;
        client.add(utf8.encode('HTTP/1.1 200 Connection established\r\n\r\n'));
        await client.flush();
        final wantMitm =
            host == kMitmHost && port == 443 && ca.ready && _mitmServer != null;
        if (wantMitm) {
          _log('MITM 接管 $host:$port');
          unawaited(CaptureLog.I.w('MITM 接管 $host:$port'));
          // 解密通道：把客户端原始字节接到本地 TLS 服务上
          final relay = await Socket.connect(
            _mitmServer!.address,
            _mitmServer!.port,
            timeout: const Duration(seconds: 5),
          );
          buf.startForwarding(relay);
        } else {
          // UI 事件只留 E听说 系域名（其他站点噪音会把关键行挤掉），全量进日志文件
          if (host.endsWith('ets100.com')) {
            _log('隧道 $host:$port${host == kMitmHost ? '（未解密，仅盲转发）' : ''}');
          }
          unawaited(CaptureLog.I.w('隧道 $host:$port'));
          // 其他一切流量：原样盲转发（强制 IPv4，避免 AAAA 优先导致超时）
          final upAddr = host == 'localhost'
              ? InternetAddress.loopbackIPv4
              : InternetAddress(host, type: InternetAddressType.IPv4);
          final up = await Socket.connect(
            upAddr,
            port,
            timeout: const Duration(seconds: 20),
          );
          buf.startForwarding(up);
        }
      } else {
        // 普通 HTTP 代理请求（绝对 URI）
        await _serveHttp(buf, headText, isTlsClient: false);
      }
    } catch (_) {
      _drop(client);
    }
  }

  // ---------------- MITM 解密侧 ----------------

  Future<void> _handleMitmClient(SecureSocket cs) async {
    final buf = _SockBuf(cs);
    try {
      await _serveHttp(buf, null, isTlsClient: true);
    } catch (_) {}
    _drop(cs);
  }

  /// 解析并逐条处理 HTTP 请求（支持 keep-alive）。
  /// [firstHead] 非空表示第一个请求头已经读好（plain 代理路径）。
  Future<void> _serveHttp(
    _SockBuf buf,
    String? firstHead, {
    required bool isTlsClient,
  }) async {
    var headText = firstHead;
    while (true) {
      if (headText == null) {
        final head = await buf.readUntil(_crlfcrlf, 64 * 1024);
        if (head == null) return;
        headText = utf8.decode(head, allowMalformed: true);
      }
      final lines = headText.substring(0, headText.length - 4).split('\r\n');
      final reqParts = lines.first.split(' ');
      if (reqParts.length < 2) return;
      final method = reqParts[0].toUpperCase();
      var path = reqParts[1];
      final headers = <String, String>{};
      for (var i = 1; i < lines.length; i++) {
        final c = lines[i].indexOf(':');
        if (c > 0) {
          headers[lines[i].substring(0, c).trim().toLowerCase()] = lines[i]
              .substring(c + 1)
              .trim();
        }
      }

      // 普通 http 代理：请求行是绝对 URI，拆出真实 host/port 与 origin-form 路径
      var upHost = headers['host']?.split(':').first.toLowerCase() ?? kMitmHost;
      var upPort = 80;
      if (!isTlsClient) {
        if (path.toLowerCase().startsWith('http://')) {
          final uri = Uri.parse(path);
          upHost = uri.host;
          upPort = uri.port;
          path = uri.path + (uri.hasQuery ? '?${uri.query}' : '');
          if (path.isEmpty) path = '/';
        } else {
          return;
        }
      } else {
        upPort = 443;
      }

      // Chromium 对较大 POST 会先发 Expect: 100-continue 等回执才发请求体，
      // 不回应就会双方死等（sync-v2 永远卡住）
      if ((headers['expect'] ?? '').toLowerCase().contains('100-continue')) {
        buf.socket.add(utf8.encode('HTTP/1.1 100 Continue\r\n\r\n'));
        await buf.socket.flush();
      }

      Uint8List body = Uint8List(0);
      final te = headers['transfer-encoding']?.toLowerCase() ?? '';
      if (te.contains('chunked')) {
        body = await buf.readChunked() ?? Uint8List(0);
      } else {
        final cl = int.tryParse(headers['content-length'] ?? '') ?? 0;
        if (cl > 0) {
          body = await buf.readBytes(cl) ?? Uint8List(0);
          if (body.length < cl) return;
        }
      }

      final keep = await _forward(
        buf.socket,
        method,
        path,
        headers,
        body,
        upHost: upHost,
        upPort: upPort,
        requestPath: path,
      );
      if (!keep) return;
      headText = null;
    }
  }

  /// 转发一条请求到上游并把响应回传；返回 false = 此连接结束
  Future<bool> _forward(
    Socket client,
    String method,
    String path,
    Map<String, String> reqHeaders,
    Uint8List body, {
    required String upHost,
    required int upPort,
    required String requestPath,
  }) async {
    final host = upHost == kMitmHost;
    final isSync = requestPath.contains(kSyncV2Path);
    var sendBody = body;
    String? resource;
    String? entity;

    // ---- 提取 resource/entity（学习满分要用，不限路由）----
    if (host && body.isNotEmpty) {
      try {
        (resource, entity) = _extractApiInfo(
          utf8.decode(body, allowMalformed: true),
        );
      } catch (_) {}
    }

    // ---- 命中改分接口：按设置改写（失败原样放行）----
    if (host && isSync && body.isNotEmpty) {
      _bump((s) => s.copyWith(intercepted: s.intercepted + 1));
      final r = _rules;
      final tag = 'sync-v2 entity=${entity ?? '?'} res=${resource ?? '?'}';
      _log(
        '命中 $tag 规则:改分${r.scoreOn ? '开(目标${r.targetScore})' : '关'}/'
        '时间${r.timeOn ? '开' : '关'} body=${body.length}B',
      );
      unawaited(
        CaptureLog.I.w(
          '命中 $tag 端口=$upPort | 改分=${r.scoreOn ? "开(${r.targetScore})" : "关"} '
          '时间=${r.timeOn ? "开(${-r.timeOffsetSec}s)" : "关"} | body=${body.length}B | '
          '满分知识: full=${_homeworkFull[resource] ?? "-"} mark=${_entityMarks["$resource|$entity"] ?? "-"}',
        ),
      );
      unawaited(CaptureLog.I.dumpSync('请求体', body));
      try {
        final text = utf8.decode(body, allowMalformed: true);
        final res = rewriteApiRequestBody(
          text,
          r,
          homeworkFull: resource == null ? null : _homeworkFull[resource],
          entityMark: resource == null || entity == null
              ? null
              : _entityMarks['$resource|$entity'],
        );
        if (res.changed) {
          sendBody = Uint8List.fromList(utf8.encode(res.bodyText));
          final why = res.notes.isEmpty ? '按规则' : res.notes.first;
          _bump(
            (s) => s.copyWith(rewritten: s.rewritten + 1, lastRewrite: why),
          );
          _log('已改写 $why');
          unawaited(CaptureLog.I.w('  → 已改写（$why），转发体 ${sendBody.length}B'));
        } else {
          final why = (!r.scoreOn && !r.timeOn)
              ? '规则开关都没开'
              : (res.notes.isEmpty ? 'body 未解析出成绩结构' : res.notes.first);
          _bump((s) => s.copyWith(passed: s.passed + 1, lastRewrite: why));
          _log('未改写：$why');
          unawaited(CaptureLog.I.w('  → 未改写：$why'));
        }
      } catch (e) {
        _bump(
          (s) => s.copyWith(passed: s.passed + 1, lastRewrite: '改写异常已放行：$e'),
        );
        _log('改写异常已放行：$e');
        unawaited(CaptureLog.I.w('  → 改写异常已放行：$e'));
      }
    }

    Socket? up;
    try {
      // ---- 组装上游请求（去掉 hop-by-hop 头，重算长度）----
      final sb = StringBuffer('$method $path HTTP/1.1\r\n');
      reqHeaders.forEach((k, v) {
        if (_hopByHop.contains(k) || k == 'content-length') return;
        sb.write('$k: $v\r\n');
      });
      sb.write('host: $upHost\r\n');
      sb.write('content-length: ${sendBody.length}\r\n');
      sb.write('connection: close\r\n\r\n');
      // TLS 保持域名连接（带 SNI）；明文拨号强制 IPv4：部分域名
      // （如 cloud.tencent.com）AAAA 优先但本机 IPv6 不通，会卡到超时
      up = upPort == 443
          ? await SecureSocket.connect(
              upHost,
              upPort,
              timeout: const Duration(seconds: 20),
              onBadCertificate: (_) => false,
            )
          : await Socket.connect(
              upHost == 'localhost'
                  ? InternetAddress.loopbackIPv4
                  : InternetAddress(upHost, type: InternetAddressType.IPv4),
              upPort,
              timeout: const Duration(seconds: 20),
            );
      final sock = up;
      sock.add(utf8.encode(sb.toString()));
      if (sendBody.isNotEmpty) sock.add(sendBody);
      await sock.flush();

      // ---- 读上游响应 ----
      final ub = _SockBuf(sock);
      final respHead = await ub.readUntil(_crlfcrlf, 128 * 1024);
      if (respHead == null) return _fail(client, up, '上游无响应');
      final respText = utf8.decode(respHead, allowMalformed: true);
      final rlines = respText.substring(0, respText.length - 4).split('\r\n');
      final rheaders = <String, String>{};
      for (var i = 1; i < rlines.length; i++) {
        final c = rlines[i].indexOf(':');
        if (c > 0) {
          rheaders[rlines[i].substring(0, c).trim().toLowerCase()] = rlines[i]
              .substring(c + 1)
              .trim();
        }
      }
      Uint8List respBody;
      final rte = rheaders['transfer-encoding']?.toLowerCase() ?? '';
      final rcl = int.tryParse(rheaders['content-length'] ?? '');
      if (rte.contains('chunked')) {
        respBody = await ub.readChunked() ?? Uint8List(0);
      } else if (method == 'HEAD' || rcl == 0) {
        respBody = Uint8List(0);
      } else if (rcl != null && rcl > 0) {
        respBody = await ub.readBytes(rcl) ?? Uint8List(0);
        if (respBody.length < rcl) return _fail(client, up, '上游响应截断');
      } else {
        respBody = await ub.readToClose();
      }

      // ---- 学习满分（安卓改分的依赖）----
      if (resource != null) {
        _learn(requestPath, rheaders['content-encoding'], respBody, resource);
      }

      // ---- 成绩响应改写（界面显示的分数来自响应：详情页/作业列表）----
      var outBody = respBody;
      if (host && _isScoreDisplayPath(requestPath)) {
        outBody = _rewriteScoreResponseIfNeeded(
          requestPath,
          rheaders['content-encoding'],
          respBody,
        );
      }

      // ---- 回传：统一重定框（上游可能 chunked/无长度，客户端侧一律 content-length）----
      client.add(_rebuildRespHead(rlines, outBody.length));
      if (outBody.isNotEmpty) client.add(outBody);
      await client.flush();
      return true;
    } catch (e) {
      return _fail(client, up, '转发失败：$e');
    } finally {
      try {
        up?.destroy();
      } catch (_) {}
    }
  }

  /// 界面显示分数的接口：成绩详情页 / 作业列表 / 提交即时反馈
  static bool _isScoreDisplayPath(String path) =>
      path.contains(kRouteScoreDetail) ||
      path.contains('/g/set/list') ||
      path.contains('g/set/column-v2') ||
      path.contains(kSyncV2Path);

  /// 改写成绩响应（gzip 先解压；改完重新 gzip 回原编码），失败一律原样放行
  Uint8List _rewriteScoreResponseIfNeeded(
    String path,
    String? contentEncoding,
    Uint8List body,
  ) {
    final rules = _rules;
    if (!rules.scoreOn || body.isEmpty) return body;
    try {
      var bytes = body;
      final gz = (contentEncoding ?? '').toLowerCase().contains('gzip');
      if (gz) bytes = Uint8List.fromList(gzip.decode(body));
      final text = utf8.decode(bytes, allowMalformed: true);
      final res = rewriteScoreResponse(text, rules, route: path);
      if (!res.changed) return body;
      var out = Uint8List.fromList(utf8.encode(res.bodyText));
      if (gz) out = Uint8List.fromList(gzip.encode(out));
      unawaited(
        CaptureLog.I.w('  → 响应改写（${path.split('?').first}）：${res.note}'),
      );
      _bump((s) => s.copyWith(lastRewrite: '响应 ${res.note}'));
      return Uint8List.fromList(out);
    } catch (e) {
      unawaited(CaptureLog.I.w('  → 响应改写失败，原样放行：$e'));
      return body;
    }
  }

  bool _fail(Socket client, Socket? up, String note) {
    _log(note);
    unawaited(CaptureLog.I.w('  !! $note'));
    try {
      up?.destroy();
    } catch (_) {}
    try {
      client.add(
        utf8.encode(
          'HTTP/1.1 502 Bad Gateway\r\ncontent-length: 0\r\nconnection: close\r\n\r\n',
        ),
      );
      client.flush();
    } catch (_) {}
    _bump((s) => s.copyWith(lastNote: note));
    return false;
  }

  // ---------------- 学习满分知识 ----------------

  void _learn(
    String path,
    String? contentEncoding,
    Uint8List body,
    String resource,
  ) {
    try {
      var bytes = body;
      final ce = contentEncoding?.toLowerCase() ?? '';
      if (ce.contains('gzip')) bytes = Uint8List.fromList(gzip.decode(body));
      final text = utf8.decode(bytes, allowMalformed: true);
      final l = learnFromResponseBody(path, text);
      if (l == null) return;
      var dirty = false;
      if (l.homeworkFull != null && _homeworkFull[resource] != l.homeworkFull) {
        _homeworkFull[resource] = l.homeworkFull!;
        dirty = true;
      }
      for (final e in l.entityMarks.entries) {
        final key = '$resource|${e.key}';
        if (_entityMarks[key] != e.value) {
          _entityMarks[key] = e.value;
          dirty = true;
        }
      }
      if (dirty) _schedulePersist();
    } catch (_) {}
  }

  void _loadKnowledge() {
    try {
      final f = _knowledgeFile;
      if (f == null || !f.existsSync()) return;
      final m = jsonDecode(f.readAsStringSync()) as Map;
      (m['full'] as Map?)?.forEach((k, v) {
        final d = double.tryParse('$v');
        if (d != null) _homeworkFull['$k'] = d;
      });
      (m['marks'] as Map?)?.forEach((k, v) {
        final d = double.tryParse('$v');
        if (d != null) _entityMarks['$k'] = d;
      });
    } catch (_) {}
  }

  void _schedulePersist() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(seconds: 2), () {
      try {
        _knowledgeFile?.writeAsStringSync(
          jsonEncode({'full': _homeworkFull, 'marks': _entityMarks}),
        );
      } catch (_) {}
    });
  }

  // ---------------- 工具 ----------------

  /// 上游响应头重建：去掉 transfer-encoding/connection/content-length/keep-alive，
  /// 统一以 content-length 界定（body 已完整读到），客户端可安全 keep-alive
  Uint8List _rebuildRespHead(List<String> lines, int bodyLen) {
    final sb = StringBuffer('${lines.first}\r\n'); // 状态行
    for (var i = 1; i < lines.length; i++) {
      final lower = lines[i].toLowerCase();
      if (lower.startsWith('transfer-encoding:') ||
          lower.startsWith('connection:') ||
          lower.startsWith('content-length:') ||
          lower.startsWith('keep-alive:')) {
        continue;
      }
      sb.write('${lines[i]}\r\n');
    }
    sb.write('content-length: $bodyLen\r\n\r\n');
    return Uint8List.fromList(utf8.encode(sb.toString()));
  }

  /// 从请求体提取（resource_id, entity_id）；路由匹配与改写器保持同口径
  (String?, String?) _extractApiInfo(String bodyText) {
    try {
      final env = jsonDecode(bodyText);
      if (env is! Map || env['body'] is! String) return (null, null);
      final inner = jsonDecode(
        utf8.decode(
          base64.decode((env['body'] as String).replaceAll(RegExp(r'\s'), '')),
          allowMalformed: true,
        ),
      );
      if (inner is! List) return (null, null);
      for (final item in inner) {
        if (item is! Map) continue;
        final route = '${item['r'] ?? ''}'.trim();
        final isSync =
            route == kRouteSyncV2 ||
            route == '/$kRouteSyncV2' ||
            route.toLowerCase() == kRouteSyncV2 ||
            route.endsWith(kRouteSyncV2);
        if (!isSync) continue;
        final params = item['params'];
        if (params is! Map) continue;
        return (
          params['resource_id'] == null ? null : '${params['resource_id']}',
          params['entity_id'] == null ? null : '${params['entity_id']}',
        );
      }
    } catch (_) {}
    return (null, null);
  }

  void _bump(CaptureStatus Function(CaptureStatus) f) => _update(f);

  /// 记一条诊断事件（最新在前，最多 12 条）
  void _log(String msg) {
    final line = '[${_hms()}] $msg';
    _update((s) {
      final list = [line, ...s.events];
      return s.copyWith(events: list.length > 60 ? list.sublist(0, 60) : list);
    });
  }

  static String _hms() {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  void _drop(Socket s) {
    try {
      s.destroy();
    } catch (_) {}
  }

  static const _crlfcrlf = [13, 10, 13, 10];
  static const _hopByHop = {
    'proxy-connection',
    'keep-alive',
    'proxy-authenticate',
    'proxy-authorization',
    'te',
    'trailer',
    'upgrade',
    'connection',
  };
}

/// Socket 缓冲读取器：头/体解析用；CONNECT 隧道建立后切换为纯转发。
class _SockBuf {
  final Socket socket;
  final List<int> _data = [];
  bool _closed = false;
  Socket? _forwardTo;
  final _waiters = <Completer<void>>[];

  _SockBuf(this.socket) {
    socket.listen(
      _onData,
      onDone: _onClosed,
      onError: (Object _) => _onClosed(),
    );
  }

  void _onData(Uint8List chunk) {
    final fwd = _forwardTo;
    if (fwd != null) {
      try {
        fwd.add(chunk);
      } catch (_) {
        _onClosed();
      }
      return;
    }
    _data.addAll(chunk);
    _notify();
  }

  void _onClosed() {
    _closed = true;
    _notify();
  }

  void _notify() {
    for (final c in List.of(_waiters)) {
      if (!c.isCompleted) c.complete();
    }
    _waiters.clear();
  }

  Future<void> _wait() {
    final c = Completer<void>();
    _waiters.add(c);
    return c.future;
  }

  /// 隧道模式：把已缓冲字节与后续字节全部转发给 [other]
  void startForwarding(Socket other) {
    _forwardTo = other;
    if (_data.isNotEmpty) {
      other.add(Uint8List.fromList(_data));
      _data.clear();
    }
    socket.flush();
    // 对端的关闭同步回来
    other.listen(
      (Uint8List d) {
        try {
          socket.add(d);
        } catch (_) {
          other.destroy();
          socket.destroy();
        }
      },
      onDone: () {
        try {
          socket.close();
        } catch (_) {}
      },
      onError: (Object _) {
        socket.destroy();
      },
    );
  }

  bool get closed => _closed;

  Future<Uint8List?> readBytes(int n) async {
    while (_data.length < n && !_closed) {
      await _wait();
    }
    final take = min(n, _data.length);
    if (take == 0) return null;
    final out = Uint8List.fromList(_data.sublist(0, take));
    _data.removeRange(0, take);
    return out;
  }

  Future<Uint8List?> readUntil(List<int> pattern, int max) async {
    while (true) {
      final idx = _indexOf(_data, pattern);
      if (idx >= 0 && idx + pattern.length <= max) {
        final out = Uint8List.fromList(_data.sublist(0, idx + pattern.length));
        _data.removeRange(0, idx + pattern.length);
        return out;
      }
      if (_data.length > max) return null;
      if (_closed) return null;
      await _wait();
    }
  }

  Future<String?> readLine() async {
    while (true) {
      final idx = _indexOf(_data, const [13, 10]);
      if (idx >= 0) {
        final s = utf8.decode(_data.sublist(0, idx), allowMalformed: true);
        _data.removeRange(0, idx + 2);
        return s;
      }
      if (_data.length > 65536) return null;
      if (_closed) {
        if (_data.isEmpty) return null;
        final s = utf8.decode(_data, allowMalformed: true);
        _data.clear();
        return s;
      }
      await _wait();
    }
  }

  Future<Uint8List?> readChunked() async {
    final out = BytesBuilder(copy: false);
    while (true) {
      final line = await readLine();
      if (line == null) return null;
      final size = int.tryParse(line.split(';').first.trim(), radix: 16);
      if (size == null) return null;
      if (size == 0) {
        while (true) {
          final t = await readLine();
          if (t == null || t.isEmpty) break;
        }
        return out.toBytes();
      }
      final chunk = await readBytes(size);
      if (chunk == null || chunk.length < size) return null;
      out.add(chunk);
      await readLine(); // 块尾 CRLF
    }
  }

  Future<Uint8List> readToClose() async {
    while (!_closed) {
      await _wait();
    }
    final out = Uint8List.fromList(_data);
    _data.clear();
    return out;
  }

  static int _indexOf(List<int> hay, List<int> needle) {
    if (needle.isEmpty || hay.length < needle.length) return -1;
    outer:
    for (var i = 0; i <= hay.length - needle.length; i++) {
      for (var j = 0; j < needle.length; j++) {
        if (hay[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }
}
