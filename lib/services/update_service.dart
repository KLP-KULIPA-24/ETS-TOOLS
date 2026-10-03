import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'settings_service.dart';

/// 官网上读到的发布信息
class ReleaseInfo {
  final String version; // 归一化后的版本号，如 0.8 / 0.9 / 0.9.1
  final String? notes; // 可选：更新说明
  final String url; // 可选：下载落地页（默认官网首页）

  const ReleaseInfo({required this.version, this.notes, required this.url});
}

enum UpdateStatus { upToDate, newer, failed }

class UpdateResult {
  final UpdateStatus status;
  final String localVersion;
  final ReleaseInfo? remote;
  final String? error;

  const UpdateResult({
    required this.status,
    required this.localVersion,
    this.remote,
    this.error,
  });

  bool get hasUpdate => status == UpdateStatus.newer;
}

/// 版本检测：读官网上的版本号，跟本地 [kAppVersion] 比。
/// 只请求白名单主机（https + klp-kulipa-24.github.io），任何异常都归结为"没查到"。
class UpdateService {
  static final UpdateService I = UpdateService._();
  UpdateService._();

  /// 官网首页（人看的）与机器读的版本文件
  static const siteUrl = 'https://klp-kulipa-24.github.io/ETS-TOOLS/';
  static const versionJsonUrl = '${siteUrl}version.json';
  static const _host = 'klp-kulipa-24.github.io';
  static const _timeout = Duration(seconds: 8);

  /// 只允许 https + 白名单主机（顺带挡掉内网 / 回环 / 保留地址）
  static bool isAllowed(Uri u) => u.scheme == 'https' && u.host == _host;

  Future<UpdateResult> check() async {
    final local = kAppVersion;
    final versionUri = Uri.tryParse(versionJsonUrl);
    final siteUri = Uri.tryParse(siteUrl);
    if (versionUri == null ||
        siteUri == null ||
        !isAllowed(versionUri) ||
        !isAllowed(siteUri)) {
      return UpdateResult(
        status: UpdateStatus.failed,
        localVersion: local,
        error: '地址不合法',
      );
    }
    try {
      // 1) 优先 version.json：发版时只改这一个文件
      final r = await http.get(versionUri).timeout(_timeout);
      if (r.statusCode == 200) {
        final remote = parseVersionFile(utf8.decode(r.bodyBytes));
        if (remote != null) return _compare(local, remote);
      }
      // 2) 回退：抓官网首页，读 nav-ver / foot-ver 里的版本号
      final p = await http.get(siteUri).timeout(_timeout);
      if (p.statusCode != 200) {
        return UpdateResult(
          status: UpdateStatus.failed,
          localVersion: local,
          error: 'HTTP ${p.statusCode}',
        );
      }
      final remote = parseHtmlVersion(utf8.decode(p.bodyBytes));
      if (remote == null) {
        return UpdateResult(
          status: UpdateStatus.failed,
          localVersion: local,
          error: '官网里没找到版本号',
        );
      }
      return _compare(local, remote);
    } catch (_) {
      return UpdateResult(
        status: UpdateStatus.failed,
        localVersion: local,
        error: '网络不可用',
      );
    }
  }

  /// version.json：`{"version":"0.8","notes":"…","url":"…"}`；也容忍纯文本版本号。
  /// url 只收白名单主机，json 坏了就退回纯文本解析。
  static ReleaseInfo? parseVersionFile(String body) {
    final text = body.trim();
    if (text.startsWith('{')) {
      try {
        final j = jsonDecode(text);
        if (j is Map) {
          final v = normalizeVersion('${j['version'] ?? ''}');
          if (v != null) {
            final notes = '${j['notes'] ?? ''}'.trim();
            return ReleaseInfo(
              version: v,
              notes: notes.isEmpty ? null : notes,
              url: safeUrl('${j['url'] ?? ''}') ?? siteUrl,
            );
          }
        }
      } catch (_) {
        // JSON 坏了就落到下面的纯文本解析
      }
    }
    final v = normalizeVersion(text);
    return v == null ? null : ReleaseInfo(version: v, url: siteUrl);
  }

  /// 首页里找 V0.8 这种标记（nav-ver / foot-ver 优先，再退到标题）
  static ReleaseInfo? parseHtmlVersion(String html) {
    final patterns = [
      RegExp(r'class="(?:nav-ver|foot-ver)"[^>]*>\s*[Vv]?([0-9][0-9.]*)'),
      RegExp(r'<title[^>]*>[^<]*?[Vv] ?([0-9][0-9.]*)'),
    ];
    for (final re in patterns) {
      final m = re.firstMatch(html);
      final v = m == null ? null : normalizeVersion(m.group(1) ?? '');
      if (v != null) return ReleaseInfo(version: v, url: siteUrl);
    }
    return null;
  }

  /// 只放行白名单主机（https）的链接，其余一律回落到官网首页
  static String? safeUrl(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final u = Uri.tryParse(t);
    if (u == null || !isAllowed(u)) return null;
    return u.toString();
  }

  /// 'V0.8.' → '0.8'；去掉尾部 .0（0.8.0 与 0.8 视为同一版本）；非法返回 null
  static String? normalizeVersion(String raw) {
    final m = RegExp(r'(\d+(?:\.\d+)*)').firstMatch(raw);
    if (m == null) return null;
    final parts = m
        .group(1)!
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    while (parts.length > 1 && parts.last == 0) {
      parts.removeLast();
    }
    return parts.join('.');
  }

  /// 语义化比较：负数 = local 旧（有更新）／0 = 相同／正数 = local 更新。
  /// 逐段按整数比（0.10 > 0.9），缺位补 0（0.8 与 0.8.0 相同）。
  static int compareVersions(String local, String remote) {
    final a = local.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final b = remote.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final n = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (y != x) return x - y;
    }
    return 0;
  }

  UpdateResult _compare(String localRaw, ReleaseInfo remote) {
    final local = normalizeVersion(localRaw) ?? localRaw;
    // 本地比官网新（例如自测版）时按最新处理，不提示降级
    final newer = compareVersions(local, remote.version) < 0;
    return UpdateResult(
      status: newer ? UpdateStatus.newer : UpdateStatus.upToDate,
      localVersion: local,
      remote: remote,
    );
  }
}
