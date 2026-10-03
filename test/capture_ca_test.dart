import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:e_ets_helper/services/capture_ca.dart';

void main() {
  test('CA 生成 → 持久化复用 → 签发叶子证书 → 真实 TLS 握手', () async {
    final dir = await Directory.systemTemp.createTemp('ets_ca_test');
    addTearDown(() => dir.delete(recursive: true));

    final ca = CaptureCa();
    await ca.ensureReady(dir);

    // CA 与私钥已持久化
    expect(ca.caCertPem, contains('BEGIN CERTIFICATE'));
    expect(ca.caCertPath, isNotEmpty);
    expect(File(ca.caCertPath).existsSync(), isTrue);

    // 再次加载：走持久化路径，CA 保持一致、叶子链重新签发不崩
    final ca2 = CaptureCa();
    await ca2.ensureReady(dir);
    expect(ca2.caCertPem, ca.caCertPem, reason: '重启后应复用同一 CA');
    expect(ca2.securityContext, isNotNull);

    // 用签好的证书起一个真实 TLS 服务并握手，
    // 客户端不信任我们的 CA（onBadCertificate 返回 true 放行），
    // 借机校验服务端出示的正是 MITM 主机的叶子证书。
    final server = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      ca.securityContext,
    );
    final subject = Completer<String>();
    server.listen((s) => s.listen((_) {}, onDone: () => s.destroy()));
    final client = await SecureSocket.connect(
      InternetAddress.loopbackIPv4,
      server.port,
      onBadCertificate: (cert) {
        if (!subject.isCompleted) subject.complete(cert.subject);
        return true;
      },
    );
    await client.close();
    await server.close();

    final s = await subject.future;
    expect(s, contains('api.ets100.com'), reason: '叶子证书的 CN/SAN 必须是 MITM 主机');
  });

  test('导出 CA 与叶子证书供 openssl 诊断', () async {
    final dir = await Directory.systemTemp.createTemp('ets_ca_dump');
    final ca = CaptureCa();
    await ca.ensureReady(dir);
    await File('${dir.path}/ca.pem').writeAsString(ca.caCertPem);
    await File('${dir.path}/leaf_chain.pem').writeAsString(ca.leafChainPem);
    // ignore: avoid_print
    print('DUMP_DIR=${dir.path}');
  });
}
