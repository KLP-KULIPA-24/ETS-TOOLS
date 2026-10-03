import 'package:e_ets_helper/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 版本检测：取版本号 / 比大小 / 只信任白名单主机
void main() {
  group('版本号归一化', () {
    test('去掉 V 前缀与尾部 .0', () {
      expect(UpdateService.normalizeVersion('V0.8'), '0.8');
      expect(UpdateService.normalizeVersion('0.8.0'), '0.8');
      expect(UpdateService.normalizeVersion('v1.2.3'), '1.2.3');
      expect(UpdateService.normalizeVersion('版本 V0.10 '), '0.10');
    });

    test('读不到数字返回 null', () {
      expect(UpdateService.normalizeVersion(''), isNull);
      expect(UpdateService.normalizeVersion('最新版'), isNull);
    });
  });

  group('版本比较', () {
    test('同版本（含补零）视为一致', () {
      expect(UpdateService.compareVersions('0.8', '0.8'), 0);
      expect(UpdateService.compareVersions('0.8', '0.8.0'), 0);
      expect(UpdateService.compareVersions('0.8.0', '0.8'), 0);
    });

    test('按整数逐段比，不是字符串比', () {
      expect(UpdateService.compareVersions('0.8', '0.9'), lessThan(0));
      expect(UpdateService.compareVersions('0.9', '0.10'), lessThan(0));
      expect(UpdateService.compareVersions('1.0', '0.9'), greaterThan(0));
      expect(UpdateService.compareVersions('0.8', '0.8.1'), lessThan(0));
    });
  });

  group('从官网内容里取版本', () {
    test('version.json 正常读取', () {
      final info = UpdateService.parseVersionFile(
        '{"version":"0.9","notes":"修了些问题","url":"https://klp-kulipa-24.github.io/ETS-TOOLS/"}',
      );
      expect(info, isNotNull);
      expect(info!.version, '0.9');
      expect(info.notes, '修了些问题');
      expect(info.url, UpdateService.siteUrl);
    });

    test('非白名单的 url 一律回落官网首页', () {
      final evil = UpdateService.parseVersionFile(
        '{"version":"0.9","url":"https://example.com/x"}',
      );
      expect(evil!.url, UpdateService.siteUrl);
      final insecure = UpdateService.parseVersionFile(
        '{"version":"0.9","url":"http://klp-kulipa-24.github.io/ETS-TOOLS/"}',
      );
      expect(insecure!.url, UpdateService.siteUrl);
      final loopback = UpdateService.parseVersionFile(
        '{"version":"0.9","url":"https://127.0.0.1/x"}',
      );
      expect(loopback!.url, UpdateService.siteUrl);
    });

    test('JSON 坏了就退回纯文本版本号', () {
      final info = UpdateService.parseVersionFile('{"version": "0.9"');
      expect(info?.version, '0.9');
    });

    test('首页读 nav-ver / foot-ver（拿不到就返回 null）', () {
      final nav = UpdateService.parseHtmlVersion(
        '<a class="brand"><span class="nav-ver">V0.8</span></a>',
      );
      expect(nav?.version, '0.8');
      final foot = UpdateService.parseHtmlVersion(
        '<div class="foot-nm">E听说助手 <span class="foot-ver">V1.2</span></div>',
      );
      expect(foot?.version, '1.2');
      expect(UpdateService.parseHtmlVersion('<p>Android 7.0+</p>'), isNull);
    });
  });

  group('请求地址白名单', () {
    test('只放行 https 的官网域名（主站 + 备用站）', () {
      expect(
        UpdateService.isAllowed(
          Uri.parse('https://klp-kulipa-24.github.io/ETS-TOOLS/'),
        ),
        isTrue,
      );
      expect(
        UpdateService.isAllowed(
          Uri.parse('https://ets-tools.klp-kulipa.workers.dev/version.json'),
        ),
        isTrue,
      );
      expect(UpdateService.isAllowed(Uri.parse('http://klp-kulipa-24.github.io/')), isFalse);
      expect(UpdateService.isAllowed(Uri.parse('https://example.com/')), isFalse);
      expect(UpdateService.isAllowed(Uri.parse('https://127.0.0.1/')), isFalse);
      expect(UpdateService.isAllowed(Uri.parse('https://192.168.1.10/')), isFalse);
      expect(UpdateService.isAllowed(Uri.parse('https://localhost/')), isFalse);
      expect(
        UpdateService.isAllowed(
          Uri.parse('https://ets-tools.klp-kulipa.workers.dev.evil.com/'),
        ),
        isFalse,
      );
    });

    test('站点顺序：主站在前，备用站兜底', () {
      expect(UpdateService.siteUrls.first, UpdateService.siteUrl);
      expect(UpdateService.siteUrls.last, UpdateService.backupSiteUrl);
    });
  });
}
