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
/// 只请求白名单主机（https + 官网域名），任何异常都归结为"没查到"。
/// 主站连不上（国内可能访问不了 GitHub Pages）时自动改用备用站。
class UpdateService {
  static final UpdateService I = UpdateService._();
  UpdateService._();

  /// 主站：GitHub Pages（始终最新）；机器读的版本文件放在站点根
  static const siteUrl = 'https://klp-kulipa-24.github.io/ETS-TOOLS/';
  static const versionJsonUrl = '${siteUrl}version.json';

  /// 备用站（Cloudflare Workers，内容与主站一致）：主站不通时兜底
  static const backupSiteUrl = 'https://ets-tools.klp-kulipa.workers.dev/';

  /// 依次尝试的站点：先主站，再备用站
  static const siteUrls = [siteUrl, backupSiteUrl];

  static const _hosts = {
    'klp-kulipa-24.github.io',
    'ets-tools.klp-kulipa.workers.dev',
  };
  static const _timeout = Duration(seconds: 8);

  /// 只允许 https + 白名单主机（顺带挡掉内网 / 回环 / 保留地址）
  static bool isAllowed(Uri u) =>
      u.scheme == 'https' && _hosts.contains(u.host);

  String? _lastSiteError;

  Future<UpdateResult> check() async {
    final local = kAppVersion;
    // 逐个站点问：任一站点拿到版本号就返回；全都不行才算失败
    var lastError = '网络不可用';
    for (final site in siteUrls) {
      final r = await _checkSite(site, local);
      if (r != null) return r;
      lastError = _lastSiteError ?? lastError;
    }
    return UpdateResult(
      status: UpdateStatus.failed,
      localVersion: local,
      error: lastError,
    );
  }

  /// 查一个站点：先 version.json，再回退到首页的 nav-ver / foot-ver；查不到返回 null
  Future<UpdateResult?> _checkSite(String site, String local) async {
    final siteUri = Uri.tryParse(site);
    final versionUri = Uri.tryParse('${site}version.json');
    if (siteUri == null ||
        versionUri == null ||
        !isAllowed(siteUri) ||
        !isAllowed(versionUri)) {
      _lastSiteError = '地址不合法';
      return null;
    }
    try {
      // 1) 优先 version.json：发版时只改这一个文件
      final r = await http.get(versionUri).timeout(_timeout);
      if (r.statusCode == 200) {
        final remote = parseVersionFile(utf8.decode(r.bodyBytes));
        if (remote != null) return _compare(local, remote);
      }
      // 2) 回退：抓首页，读 nav-ver / foot-ver 里的版本号
      final p = await http.get(siteUri).timeout(_timeout);
      if (p.statusCode != 200) {
        _lastSiteError = 'HTTP ${p.statusCode}';
        return null;
      }
      final remote = parseHtmlVersion(utf8.decode(p.bodyBytes));
      if (remote == null) {
        _lastSiteError = '官网里没找到版本号';
        return null;
      }
      return _compare(local, remote);
    } catch (_) {
      _lastSiteError = '网络不可用';
      return null;
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
