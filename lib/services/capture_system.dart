import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shell_service.dart';

/// 代理接入模式：pac = 只有 E听说 系域名走引擎（其余直连，永不断网）
///                 system = 全局系统代理（全流量进引擎，覆盖更全但更脆弱）
enum ProxyMode { pac, system }

/// 修改模块的系统接入层：
/// - Windows：注册表设置/还原系统代理（HKCU，免管理员）+ certutil 装用户根证书
/// - Android：root 执行 settings put/delete global http_proxy
class CaptureSystem {
  CaptureSystem._();

  static const _inetKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
  static const _kProxyBackup = 'captureProxyBackup';

  // ---------------- PAC 模式（推荐：仅 E听说 走引擎，其余直连） ----------------

  static const _kProxyMode = 'captureProxyMode';
  static const _kPacBackup = 'capturePacBackup';
  static const _pacName = 'capture-proxy.pac';

  static Future<ProxyMode> proxyMode() async {
    try {
      final sp = await SharedPreferences.getInstance();
      return (sp.getString(_kProxyMode) == 'system')
          ? ProxyMode.system
          : ProxyMode.pac;
    } catch (_) {
      return ProxyMode.pac;
    }
  }

  static Future<void> setProxyMode(ProxyMode m) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kProxyMode, m.name);
  }

  /// PAC 规则：ets100 系域名 → 引擎；其余 → DIRECT
  static String _pacText(int port) {
    final b = StringBuffer();
    b.writeln('function FindProxyForURL(url, host) {');
    b.writeln('  host = host.toLowerCase();');
    b.writeln(
      '  if (host.indexOf("ets100") >= 0) { return "PROXY 127.0.0.1:$port"; }',
    );
    b.writeln('  return "DIRECT";');
    b.writeln('}');
    return b.toString();
  }

  /// Windows 启用 PAC（AutoConfigURL 指向本应用生成的 pac 文件）
  static Future<String?> setPacWin(int port) async {
    if (!Platform.isWindows) return '仅支持 Windows';
    try {
      final sp = await SharedPreferences.getInstance();
      final dir = Directory(
        p.join((await getApplicationSupportDirectory()).path, 'capture'),
      )..createSync(recursive: true);
      final pacFile = File(p.join(dir.path, _pacName));
      pacFile.writeAsStringSync(_pacText(port));
      if (sp.getString(_kPacBackup) == null) {
        final autoUrl = await _regGet('AutoConfigURL') ?? '';
        final enable = await _regGet('ProxyEnable') ?? '0';
        await sp.setString(_kPacBackup, '$autoUrl|$enable');
      }
      // PAC 与固定代理互斥：关固定代理 + 指向 pac
      await _regSet('ProxyEnable', '0', dword: true);
      await _regSet('AutoConfigURL', Uri.file(pacFile.path).toString());
      return null;
    } catch (e) {
      return '设置 PAC 失败：$e';
    }
  }

  /// 还原 PAC（同时清掉固定代理残留）
  static Future<String?> restorePacWin() async {
    if (!Platform.isWindows) return null;
    try {
      final sp = await SharedPreferences.getInstance();
      final backup = sp.getString(_kPacBackup);
      final parts = (backup ?? '').split('|');
      final autoUrl = parts.isNotEmpty ? parts[0].trim() : '';
      final enable = parts.length > 1 ? parts[1].trim() : '0';
      if (autoUrl.isEmpty) {
        await _regDel('AutoConfigURL');
      } else {
        await _regSet('AutoConfigURL', autoUrl);
      }
      await _regSet('ProxyEnable', enable == '1' ? '1' : '0', dword: true);
      await sp.remove(_kPacBackup);
      // 固定代理若还指着本机也一并还原
      final server = await _regGet('ProxyServer');
      if (server != null && server.contains('127.0.0.1:')) {
        await restoreSystemProxy();
      }
      return null;
    } catch (e) {
      return '还原 PAC 失败：$e';
    }
  }

  /// PAC 是否正在生效（AutoConfigURL 指向我们的 pac 文件）
  static Future<bool> isPacOurs() async {
    if (!Platform.isWindows) return false;
    final autoUrl = (await _regGet('AutoConfigURL')) ?? '';
    return autoUrl.contains(_pacName);
  }

  // ---------------- Windows 系统代理 ----------------

  /// 当前系统代理是否指向本引擎（用于判断"已设置"状态与残留）
  static Future<bool> isProxyOurs(int port) async {
    if (!Platform.isWindows) return false;
    if (await isPacOurs()) return true;
    final server = await _regGet('ProxyServer');
    return server != null && server.trim() == '127.0.0.1:$port';
  }

  /// 一键设置系统代理（先备份用户原值），失败返回错误文案
  static Future<String?> setSystemProxy(int port) async {
    if (!Platform.isWindows) return '仅支持 Windows';
    try {
      final sp = await SharedPreferences.getInstance();
      if (sp.getString(_kProxyBackup) == null) {
        final enable = await _regGet('ProxyEnable') ?? '0';
        final server = await _regGet('ProxyServer') ?? '';
        final bypass = await _regGet('ProxyOverride') ?? '';
        await sp.setString(_kProxyBackup, '$enable\n$server\n$bypass');
      }
      await _regSet('ProxyEnable', '1', dword: true);
      await _regSet('ProxyServer', '127.0.0.1:$port');
      // 本机/局域网直连，其余（含 api.ets100.com）走引擎
      const bypass = '<local>;localhost;127.*;10.*;172.16.*;192.168.*';
      await _regSet('ProxyOverride', bypass);
      return null;
    } catch (e) {
      return '设置系统代理失败：$e';
    }
  }

  /// 还原系统代理为开启引擎前的状态
  static Future<String?> restoreSystemProxy() async {
    if (!Platform.isWindows) return null;
    try {
      final sp = await SharedPreferences.getInstance();
      final backup = sp.getString(_kProxyBackup);
      if (backup == null) {
        // 没有备份：直接关掉代理
        await _regSet('ProxyEnable', '0', dword: true);
        await _regDel('ProxyServer');
        return null;
      }
      final parts = backup.split('\n');
      String get(int i) => parts.length > i ? parts[i] : '';
      final enable = get(0).trim() == '1' ? '1' : '0';
      await _regSet('ProxyEnable', enable, dword: true);
      final server = get(1).trim();
      if (server.isEmpty) {
        await _regDel('ProxyServer');
      } else {
        await _regSet('ProxyServer', server);
      }
      final bypass = get(2).trim();
      if (bypass.isEmpty) {
        await _regDel('ProxyOverride');
      } else {
        await _regSet('ProxyOverride', bypass);
      }
      await sp.remove(_kProxyBackup);
      return null;
    } catch (e) {
      return '还原系统代理失败：$e';
    }
  }

  static Future<String?> _regGet(String name) async {
    final r = await Process.run('reg', ['query', _inetKey, '/v', name]);
    if (r.exitCode != 0) return null;
    final m = RegExp(
      r'REG_(SZ|DWORD)\s+(\S+)$',
      multiLine: true,
    ).firstMatch(r.stdout as String);
    if (m == null) return null;
    var v = m.group(2)!;
    if (v.startsWith('0x')) v = v.replaceFirst('0x', '');
    return v;
  }

  static Future<void> _regSet(
    String name,
    String value, {
    bool dword = false,
  }) async {
    final args = [
      'add',
      _inetKey,
      '/v',
      name,
      '/t',
      dword ? 'REG_DWORD' : 'REG_SZ',
      '/d',
      value,
      '/f',
    ];
    final r = await Process.run('reg', args);
    if (r.exitCode != 0) throw Exception(r.stderr ?? r.stdout);
  }

  static Future<void> _regDel(String name) async {
    await Process.run('reg', ['delete', _inetKey, '/v', name, '/f']);
  }

  // ---------------- Windows 证书 ----------------

  /// 用 certutil 把 CA 装进当前用户"受信任的根证书颁发机构"（免管理员）。
  /// [caPemPath] 是 CA 证书文件路径；返回错误文案或 null=成功。
  static Future<String?> installCaWin(String caPemPath) async {
    if (!Platform.isWindows) return '仅支持 Windows';
    final r = await Process.run('certutil', [
      '-user',
      '-addstore',
      'Root',
      caPemPath,
    ]);
    if (r.exitCode != 0) {
      return '证书安装失败：${(r.stderr as String?)?.trim() ?? r.stdout}';
    }
    return null;
  }

  /// 检查 CA 是否已装进当前用户根证书库（按 CN 匹配）
  static Future<bool> isCaInstalledWin(String cn) async {
    if (!Platform.isWindows) return false;
    final r = await Process.run('certutil', ['-user', '-store', 'Root']);
    return (r.stdout as String).contains(cn);
  }

  // ---------------- Android 全局代理 ----------------

  /// 设置全局 http_proxy（root）。返回错误文案或 null=成功。
  static Future<String?> setProxyAndroid(int port) async {
    final sp = await SharedPreferences.getInstance();
    final probe = await ShellService.probe();
    if (probe == null || (!probe.root && !probe.shizuku)) {
      return '需要 Root 或 Shizuku 提权通道';
    }
    if (sp.getString(_kProxyBackupAndroid) == null) {
      final cur = await ShellService.exec('settings get global http_proxy');
      final curOut = cur?.out.trim() ?? '';
      if (curOut.isNotEmpty && curOut != 'null') {
        await sp.setString(_kProxyBackupAndroid, curOut);
      }
    }
    final r = await ShellService.exec(
      'settings put global http_proxy 127.0.0.1:$port',
    );
    if (r == null || r.exit != 0) return '设置全局代理失败（${r?.err ?? '无输出'}）';
    return null;
  }

  static const _kProxyBackupAndroid = 'captureProxyBackupAndroid';

  /// 还原安卓全局代理
  static Future<String?> restoreProxyAndroid() async {
    final sp = await SharedPreferences.getInstance();
    final backup = sp.getString(_kProxyBackupAndroid);
    final cmd = (backup == null || backup.isEmpty || backup == ':0')
        ? 'settings delete global http_proxy'
        : 'settings put global http_proxy $backup';
    final r = await ShellService.exec(cmd);
    await sp.remove(_kProxyBackupAndroid);
    if (r == null || r.exit != 0) return '还原全局代理失败';
    return null;
  }

  /// 安卓当前全局代理是否指向本引擎
  static Future<bool> isProxyOursAndroid(int port) async {
    if (!Platform.isAndroid) return false;
    final r = await ShellService.exec('settings get global http_proxy');
    return '${r?.out.trim()}' == '127.0.0.1:$port';
  }

  /// E听说 客户端是否正在运行
  /// （Windows 端主进程 Ets.exe / EtsShell.exe；安卓包名 com.ets100.secondary）
  static Future<bool> isEtsRunning() async {
    try {
      if (Platform.isWindows) {
        for (final name in const ['Ets.exe', 'EtsShell.exe']) {
          final r = await Process.run('tasklist', [
            '/FI',
            'IMAGENAME eq $name',
            '/NH',
            '/FO',
            'CSV',
          ]);
          final out = '${r.stdout ?? ''}';
          if (out.contains('"$name"')) return true;
        }
        return false;
      }
      if (Platform.isAndroid) {
        final r = await ShellService.exec(
          'pidof com.ets100.secondary || ps -A | grep ets100',
        );
        final out = (r?.out ?? '').trim();
        return out.isNotEmpty && !out.contains('no such');
      }
    } catch (e) {
      debugPrint('isEtsRunning: $e');
    }
    return false;
  }

  /// 当前系统代理若指向本机 127.0.0.1，返回其端口；否则 null
  static Future<int?> currentProxyPort() async {
    try {
      if (Platform.isWindows) {
        if (await isPacOurs()) {
          final dir = await getApplicationSupportDirectory();
          final f = File(p.join(dir.path, 'capture', _pacName));
          if (f.existsSync()) {
            final m = RegExp(r'127\.0\.0\.1:(\d+)')
                .firstMatch(f.readAsStringSync());
            if (m != null) return int.tryParse(m.group(1)!);
          }
          return null;
        }
        final server = await _regGet('ProxyServer');
        final m = RegExp(r'127\.0\.0\.1:(\d+)').firstMatch(server ?? '');
        return m == null ? null : int.tryParse(m.group(1)!);
      }
      if (Platform.isAndroid) {
        final r = await ShellService.exec('settings get global http_proxy');
        final m = RegExp(r'127\.0\.0\.1:(\d+)').firstMatch(r?.out ?? '');
        return m == null ? null : int.tryParse(m.group(1)!);
      }
    } catch (_) {}
    return null;
  }

  // ---------------- 统一入口（按平台分发） ----------------

  static bool get isWindows => Platform.isWindows;
  static bool get isAndroid => Platform.isAndroid;

  /// 平台名（UI 文案用）
  static String get platformName => isWindows ? 'Windows' : 'Android';

  /// 检查系统代理是否指向本引擎
  static Future<bool> proxyIsOurs(int port) =>
      isWindows ? isProxyOurs(port) : isProxyOursAndroid(port);

  static Future<String?> proxySet(int port) async {
    if (!isWindows) return setProxyAndroid(port);
    return (await proxyMode()) == ProxyMode.pac
        ? setPacWin(port)
        : setSystemProxy(port);
  }

  static Future<String?> proxyRestore() async {
    if (!isWindows) return restoreProxyAndroid();
    // 两种接入都还原一遍，幂等
    final a = await restorePacWin();
    return a ?? restoreSystemProxy();
  }

  /// 仅当系统代理指向本机时还原（安全版，关引擎前调用）
  static Future<String?> proxyRestoreIfOurs() async {
    final cur = await currentProxyPort();
    if (cur == null) return null;
    return proxyRestore();
  }

  /// 供主程序启动时调用：若上次会话残留了我们的系统代理设置，静默还原，
  /// 避免引擎没跑却把用户网络指向一个不存在的代理。
  static Future<void> recoverLeftover() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (isWindows) {
        if (await isPacOurs()) {
          await restorePacWin();
        }
        final server = await _regGet('ProxyServer');
        if (server != null && server.contains('127.0.0.1:')) {
          await restoreSystemProxy();
        }
      } else if (isAndroid) {
        final v = await ShellService.exec('settings get global http_proxy');
        if ('${v?.out.trim()}'.startsWith('127.0.0.1:')) {
          await restoreProxyAndroid();
        }
      } else {
        return;
      }
      await sp.remove(_kProxyBackup);
      await sp.remove(_kProxyBackupAndroid);
    } catch (e) {
      debugPrint('recoverLeftover: $e');
    }
  }
}
