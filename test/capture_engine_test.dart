import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:e_ets_helper/services/capture_engine.dart';
import 'package:e_ets_helper/services/capture_rewrite.dart';
import 'package:e_ets_helper/services/settings_service.dart';

/// 引擎管线联调：HTTP 代理 → CONNECT → MITM 解密 → 改写 → 转发 → 响应回传。
/// 上游用的是真实 api.ets100.com（无 token 会被服务端拒绝，但足够验证链路）。

/// 单订阅 socket 的持久读取器（测试辅助）
class _R {
  final Socket s;
  final _buf = <int>[];
  late final StreamSubscription<Uint8List> _sub;
  _R(this.s) {
    _sub = s.listen(_buf.addAll, onError: (Object _) {});
  }

  Future<void> _pump(bool Function() ready) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      if (ready()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('读取超时');
  }

  /// 读到 \r\n\r\n 为止（可指定额外字节数）
  Future<String> head({int extra = 0}) async {
    await _pump(() {
      final i = _find([13, 10, 13, 10]);
      return i >= 0 && _buf.length >= i + 4 + extra;
    });
    final out = utf8.decode(_buf, allowMalformed: true);
    return out;
  }

  Future<Uint8List> drainAfterIdle({
    Duration idle = const Duration(milliseconds: 400),
  }) async {
    final start = _buf.length;
    await Future<void>.delayed(idle);
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (_buf.length != start && DateTime.now().isBefore(deadline)) {
      start;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final out = Uint8List.fromList(_buf);
    return out;
  }

  void destroy() {
    _sub.cancel();
    s.destroy();
  }

  int _find(List<int> needle) {
    for (var i = 0; i <= _buf.length - needle.length; i++) {
      var hit = true;
      for (var j = 0; j < needle.length; j++) {
        if (_buf[i + j] != needle[j]) {
          hit = false;
          break;
        }
      }
      if (hit) return i;
    }
    return -1;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('引擎管线：盲转发 + MITM 改写 sync-v2', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'captureScoreOn': true,
      'captureScore': '60',
    });
    await SettingsService.I.load();

    final tempDir = await Directory.systemTemp.createTemp('ets_engine_test');
    addTearDown(() async {
      await CaptureEngine.I.stop();
      if (tempDir.existsSync()) tempDir.delete(recursive: true);
    });

    final ca = CaptureEngine.I.ca;
    await ca.ensureReady(tempDir);
    final err = await CaptureEngine.I.start(0);
    expect(err, isNull, reason: '引擎应启动成功');
    final proxyPort = CaptureEngine.I.status.value.port;
    expect(CaptureEngine.I.status.value.running, isTrue);

    // ---- 场景 1：非 MITM 主机走盲转发（本地回环 HTTP 服务）----
    final upstream = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((s) {
      s.listen((_) {}, onDone: () => s.destroy());
      s.add(utf8.encode('HTTP/1.1 200 OK\r\ncontent-length: 2\r\n\r\nhi'));
    });
    final c1 = _R(
      await Socket.connect(InternetAddress.loopbackIPv4, proxyPort),
    );
    c1.s.add(
      utf8.encode(
        'CONNECT 127.0.0.1:${upstream.port} HTTP/1.1\r\nhost: x\r\n\r\n',
      ),
    );
    final r1 = await c1.head();
    expect(r1, contains('200 Connection established'), reason: 'CONNECT 应放行');
    c1.s.add(utf8.encode('GET / HTTP/1.1\r\nhost: x\r\n\r\n'));
    final r1b = await c1.head(extra: 'hi'.length);
    expect(r1b, contains('hi'), reason: '盲转发应原样回传');
    c1.destroy();
    await upstream.close();

    // ---- 场景 2：api.ets100.com 走 MITM，sync-v2 请求被改写后转发 ----
    final c2 = _R(
      await Socket.connect(InternetAddress.loopbackIPv4, proxyPort),
    );
    c2.s.add(
      utf8.encode(
        'CONNECT api.ets100.com:443 HTTP/1.1\r\nhost: api.ets100.com:443\r\n\r\n',
      ),
    );
    expect(await c2.head(), contains('200 Connection established'));
    final tls = _R(
      await SecureSocket.secure(
        c2.s,
        host: kMitmHost,
        onBadCertificate: (_) => true,
      ),
    );

    final reqBody = jsonEncode({
      'body': base64.encode(
        utf8.encode(
          jsonEncode([
            {
              'r': kRouteSyncV2,
              'params': {
                'resource_id': '1767',
                'entity_id': '253909',
                'score': '0.0',
                'client_time': '2026-10-01 11:22:27',
                'score_detail': jsonEncode({
                  'total_score': '0.0',
                  'fluency_score': '0.0',
                  'accuracy_score': '0.0',
                  'integrity_score': '0.0',
                  'standard_score': '0.0',
                  'category': 'read_chapter',
                }),
              },
            },
          ]),
        ),
      ),
      'head': {'pid': 'androidV3', 'sign': 'test'},
    });
    final bodyBytes = utf8.encode(reqBody);
    tls.s.add(
      utf8.encode(
        'POST /m/audio/sync-v2?sn=test HTTP/1.1\r\n'
        'host: api.ets100.com\r\n'
        'content-type: application/json\r\n'
        'content-length: ${bodyBytes.length}\r\n'
        'connection: close\r\n\r\n',
      ),
    );
    tls.s.add(bodyBytes);
    final respBytes = await tls.drainAfterIdle();
    final respText = utf8.decode(respBytes, allowMalformed: true);
    // 改写发生在转发前：无论上游回什么，改写计数必须为 1
    expect(CaptureEngine.I.status.value.intercepted, 1);
    expect(
      CaptureEngine.I.status.value.rewritten,
      1,
      reason: 'read_chapter 满分 20、目标 60 → 应完成改写',
    );
    expect(
      respText.startsWith('HTTP/1.1 '),
      isTrue,
      reason: '上游可达时回真实响应（无 token 会 400），不可达时引擎兜底 502，都不应挂死',
    );
    tls.destroy();
  }, timeout: const Timeout(Duration(seconds: 60)));
}
