import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:basic_utils/basic_utils.dart';
import 'package:path/path.dart' as p;

import 'capture_rewrite.dart';

/// 本地 HTTPS 代理的证书体系：
/// 首次使用生成自签根 CA（私钥持久化到应用支持目录），引擎启动时
/// 用 CA 给 [kMitmHost] 签发叶子证书，供 MITM 解密 sync-v2 流量。
class CaptureCa {
  RSAPrivateKey? _caKey;

  /// CA 自签证书 PEM（用户安装的就是它）
  String caCertPem = '';

  /// CA 主题 DN（签发叶子证书时作为 issuer 复用）
  Map<String, String> caDn = const {};

  /// CA 证书文件路径（安装/导出用）
  String caCertPath = '';

  /// 叶子证书链 PEM（叶子 + CA，调试/诊断用）
  String leafChainPem = '';

  /// 叶子证书链（叶子 + CA），与 [securityContext] 配套
  SecurityContext? securityContext;

  bool get ready => _caKey != null && securityContext != null;

  static Directory _dirOf(Directory base) =>
      Directory(p.join(base.path, 'capture'));

  /// 加载或生成 CA，并给 MITM 主机签好叶子证书。失败抛异常由调用方兜底。
  Future<void> ensureReady(Directory supportDir) async {
    if (ready) return;
    final dir = _dirOf(supportDir);
    await dir.create(recursive: true);
    final keyFile = File(p.join(dir.path, 'ca_key.pem'));
    final certFile = File(p.join(dir.path, 'ca_cert.pem'));

    if (await keyFile.exists() && await certFile.exists()) {
      try {
        _caKey = CryptoUtils.rsaPrivateKeyFromPem(await keyFile.readAsString());
        caCertPem = await certFile.readAsString();
        caDn = _subjectOf(caCertPem);
      } catch (_) {
        _caKey = null;
      }
    }
    if (_caKey == null || caDn.isEmpty) {
      final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
      final priv = pair.privateKey as RSAPrivateKey;
      final pub = pair.publicKey as RSAPublicKey;
      caDn = {'C': 'CN', 'O': 'EtsHelper', 'CN': 'EtsHelper Capture Root CA'};
      final csr = X509Utils.generateRsaCsrPem(caDn, priv, pub);
      caCertPem = X509Utils.generateSelfSignedCertificate(
        priv,
        csr,
        3650,
        cA: true,
        serialNumber: _serial(),
        // 注意：不传 keyUsage —— basic_utils 的 KeyUsage BIT STRING
        // 编码不合 DER，BoringSSL 直接拒握手（openssl 却宽容）。
      );
      _caKey = priv;
      await keyFile.writeAsString(
        CryptoUtils.encodeRSAPrivateKeyToPem(priv),
        flush: true,
      );
      await certFile.writeAsString(caCertPem, flush: true);
    }
    caCertPath = certFile.path;
    await _signLeaf();
  }

  /// 给 MITM 主机签叶子证书并构建服务端 SecurityContext
  Future<void> _signLeaf() async {
    final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final priv = pair.privateKey as RSAPrivateKey;
    final pub = pair.publicKey as RSAPublicKey;
    final csr = X509Utils.generateRsaCsrPem(
      {'CN': kMitmHost},
      priv,
      pub,
      san: [kMitmHost],
    );
    final leaf = X509Utils.generateSelfSignedCertificate(
      _caKey!,
      csr,
      825,
      sans: [kMitmHost],
      serialNumber: _serial(),
      issuer: caDn,
      extKeyUsage: [ExtendedKeyUsage.SERVER_AUTH],
    );
    final chain = '$leaf\n$caCertPem\n';
    leafChainPem = chain;
    final keyPem = CryptoUtils.encodeRSAPrivateKeyToPem(priv);
    final ctx = SecurityContext();
    ctx.useCertificateChainBytes(utf8.encode(chain));
    ctx.usePrivateKeyBytes(utf8.encode(keyPem));
    securityContext = ctx;
  }

  Map<String, String> _subjectOf(String pem) {
    try {
      final data = X509Utils.x509CertificateFromPem(pem);
      final raw = data.tbsCertificate?.subject;
      final m = <String, String>{
        for (final e in (raw ?? const {}).entries) e.key: e.value ?? '',
      };
      if (m.isNotEmpty) return m;
    } catch (_) {}
    return {};
  }

  String _serial() {
    final rng = Random.secure();
    var v = BigInt.zero;
    for (var i = 0; i < 8; i++) {
      v = (v << 8) | BigInt.from(rng.nextInt(256));
    }
    v = v | BigInt.one; // 保证非零
    return v.toString();
  }
}
