import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../services/capture_engine.dart';
import '../../services/capture_log.dart';
import '../../services/capture_rewrite.dart';
import '../../services/capture_system.dart';
import '../../services/settings_service.dart';
import '../../services/shell_service.dart';

import '../../widgets/glass.dart';
import '../../widgets/interactive_tour.dart';
import '../../widgets/style.dart';
import '../../widgets/tour_guide.dart';

/// 高级模式的题型目录（category 来自接口 score_detail.category，中文为常用对照）
const Map<String, String> kCaptureCategoryLabels = {
  'read_chapter': '朗读短文',
  'simple_expression': '情景表达',
  'topic': '话题表达',
};

/// 修改栏：本地 HTTPS 代理拦截引擎（改成绩 / 改完成时刻）+ 证书与代理接入
class CapturePage extends StatefulWidget {
  const CapturePage({super.key});

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  bool proxySet = false;
  ProxyMode proxyMode = ProxyMode.pac;
  bool? caInstalled;
  bool etsRunning = false;

  /// 系统代理当前指向的端口（null = 不是本引擎）；与引擎监听端口不一致 = 断网
  int? proxyPort;

  // 目标成绩 / 完成时间时长（天/时/分/秒）/ 端口 输入框
  late final TextEditingController _scoreCtrl;
  late final List<TextEditingController> _timeCtrls;
  late final TextEditingController _portCtrl;
  late final Map<String, TextEditingController> _catCtrls;

  // 互动教程锚点
  final _kCapture = GlobalKey();
  final _kScore = GlobalKey();
  final _kTime = GlobalKey();

  // 证书安装状态定时探测（用户手动装完证书后状态卡自动感知）
  Timer? _certTimer;

  @override
  void initState() {
    super.initState();
    TourHub.register(2, _buildTour);
    _loadProxyMode();
    final sec = SettingsService.I;
    _scoreCtrl = TextEditingController(text: sec.captureScore);
    // -1 = 全空不修改；>=0 按四框回填（0 也要显示出来，用户能看到填的是 0）
    final dur = sec.captureTimeSec;
    if (dur >= 0) {
      final parts = [
        dur ~/ 86400,
        (dur % 86400) ~/ 3600,
        (dur % 3600) ~/ 60,
        dur % 60,
      ];
      _timeCtrls = [for (final v in parts) TextEditingController(text: '$v')];
    } else {
      _timeCtrls = [for (var i = 0; i < 4; i++) TextEditingController()];
    }
    _portCtrl = TextEditingController(text: '${sec.capturePort}');
    _catCtrls = {
      for (final c in kCaptureCategoryLabels.keys)
        c: TextEditingController(
          text: sec.captureCategoryScoreMap[c] == null
              ? ''
              : _trimNum(sec.captureCategoryScoreMap[c]!),
        ),
    };
    _refreshSystemState();
    _certTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _refreshSystemState(),
    );
  }

  static String _trimNum(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : '$v';

  @override
  void dispose() {
    TourHub.unregister(2);
    _certTimer?.cancel();
    _scoreCtrl.dispose();
    for (final c in _timeCtrls) {
      c.dispose();
    }
    _portCtrl.dispose();
    for (final c in _catCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// -1 = 全空（不修改）；>=0 = 主动提前的秒数（0 就是按提交时刻上传）
  int get _timeSec {
    final texts = [for (final c in _timeCtrls) c.text.trim()];
    if (texts.every((t) => t.isEmpty)) return -1;
    final v = [for (final t in texts) int.tryParse(t) ?? 0];
    return v[0] * 86400 + v[1] * 3600 + v[2] * 60 + v[3];
  }

  String _durationEcho(int sec) {
    final d = sec ~/ 86400;
    final h = (sec % 86400) ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    final parts = <String>[];
    if (d > 0) parts.add('$d 天');
    if (h > 0) parts.add('$h 时');
    if (m > 0) parts.add('$m 分');
    if (s > 0) parts.add('$s 秒');
    return parts.isEmpty ? '0 秒' : parts.join(' ');
  }

  Future<void> _refreshSystemState() async {
    final port = SettingsService.I.capturePort;
    final ours = await CaptureSystem.proxyIsOurs(port);
    var installed = false;
    if (CaptureSystem.isWindows) {
      installed = await CaptureSystem.isCaInstalledWin(
        'EtsHelper Capture Root CA',
      );
    }
    final ets = await CaptureSystem.isEtsRunning();
    final pp = await CaptureSystem.currentProxyPort();
    if (!mounted) return;
    setState(() {
      proxySet = ours;
      caInstalled = CaptureSystem.isWindows ? installed : null;
      etsRunning = ets;
      proxyPort = pp;
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 打开日志目录（Windows explorer；安卓拉起文件管理器，失败复制路径）
  Future<void> _openLogFolder(String path) async {
    if (Platform.isWindows) {
      if (Directory(path).existsSync()) {
        await Process.run('explorer', [path]);
      } else {
        _toast('日志目录还没生成：$path');
      }
      return;
    }
    final r = await ShellService.exec(
      'am start -a android.intent.action.VIEW -d "file://$path"',
    );
    if (r != null && r.exit == 0) return;
    await Clipboard.setData(ClipboardData(text: path));
    _toast('已复制路径：$path');
  }

  Future<void> _toggleEngine(bool on) async {
    final port = SettingsService.I.capturePort;
    if (on) {
      final err = await CaptureEngine.I.start(port);
      if (err != null) _toast('引擎启动失败：$err');
    } else {
      // 先还原代理再停引擎：顺序反了会短暂断网
      await CaptureSystem.proxyRestoreIfOurs();
      await CaptureEngine.I.stop();
    }
    await _refreshSystemState();
  }

  /// 读取 PAC / 全局 模式（Windows 生效；安卓固定全局）
  Future<void> _loadProxyMode() async {
    final m = await CaptureSystem.proxyMode();
    if (mounted) setState(() => proxyMode = m);
  }

  Future<void> _setProxy() async {
    final port = SettingsService.I.capturePort;
    // 引擎必须真的在"设置里的端口"上监听（可能用户改过端口而引擎还在旧端口）
    final s = CaptureEngine.I.status.value;
    if (!s.running || s.port != port) {
      if (s.running) await CaptureEngine.I.stop();
      final err = await CaptureEngine.I.start(port);
      if (err != null) {
        _toast('引擎启动失败：$err');
        return;
      }
    }
    final err = await CaptureSystem.proxySet(port);
    if (err != null) _toast(err);
    await _refreshSystemState();
    setState(() {});
  }

  /// 端口变更后重启引擎，并把系统代理跟着指到新端口
  Future<void> _restartEngineOnPort(int port) async {
    final wasOurs = await CaptureSystem.proxyIsOurs(port);
    await CaptureEngine.I.stop();
    final err = await CaptureEngine.I.start(port);
    if (err != null) {
      _toast('新端口启动失败：$err');
    } else if (wasOurs) {
      await CaptureSystem.proxySet(port);
    }
    await _refreshSystemState();
    if (mounted) setState(() {});
  }

  Future<void> _restoreProxy() async {
    final err = await CaptureSystem.proxyRestore();
    if (err != null) _toast(err);
    await _refreshSystemState();
    setState(() {});
  }

  Future<void> _installCa() async {
    final ca = CaptureEngine.I.ca;
    try {
      await ca.ensureReady(await getApplicationSupportDirectory());
    } catch (e) {
      _toast('证书生成失败：$e');
      return;
    }
    final err = await CaptureSystem.installCaWin(ca.caCertPath);
    if (err != null) {
      _toast(err);
    } else {
      _toast('证书已安装到当前用户受信任的根证书库');
    }
    await _refreshSystemState();
  }

  Future<void> _exportCa() async {
    final ca = CaptureEngine.I.ca;
    try {
      await ca.ensureReady(await getApplicationSupportDirectory());
    } catch (e) {
      _toast('证书生成失败：$e');
      return;
    }
    if (CaptureSystem.isAndroid) {
      // root 拷到下载目录，方便在系统设置里安装
      final r = await ShellService.exec(
        'cp "${ca.caCertPath}" /sdcard/Download/EtsHelperCA.pem',
      );
      if (r != null && r.exit == 0) {
        _toast('已导出到 /sdcard/Download/EtsHelperCA.pem');
        return;
      }
      _toast('导出到下载目录失败（需要 Root），证书文件在：${ca.caCertPath}');
      return;
    }
    // Windows：拷到文档目录
    final docs = await getApplicationDocumentsDirectory();
    final target = File('${docs.path}${Platform.pathSeparator}EtsHelperCA.pem');
    await File(ca.caCertPath).copy(target.path);
    _toast('已导出到：${target.path}');
  }

  void _saveCategoryScores() {
    final scores = <String, double>{};
    _catCtrls.forEach((cat, ctrl) {
      final v = double.tryParse(ctrl.text.trim());
      if (v != null && v >= 0) scores[cat] = v;
    });
    context.read<SettingsService>().setCaptureAdvanced(scores: scores);
  }

  /// 修改页引导：三张配置卡 + 运行状态
  List<TourStep> _buildTour() => [
    TourStep(
      _kCapture,
      '抓包拦截总开关',
      '开启后本机 127.0.0.1:端口 启动内置代理，拦截 E听说 的成绩提交接口。'
          '「设置系统代理」把流量引到引擎，关闭总开关会自动还原代理。',
    ),
    TourStep(
      _kScore,
      '目标总成绩',
      '填这份作业最终想要的总分（如 60），引擎按各小题满分占比分摊；'
          '允许超过满分。高级模式可按题型精确指定每小题得分。',
    ),
    TourStep(
      _kTime,
      '修改完成时间',
      '按 天/时/分/秒 填一个时长，提交时后台自动把完成时刻提前这么久'
          '（比如填 1 分 30 秒，完成时间看起来就是 1 分 30 秒之前）；'
          '全空表示不修改，填 0 表示按提交时刻上传。',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassScaffold(
      wall: false,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (MediaQuery.of(context).size.width >= 700)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '修改',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          _buildCaptureCard(context, cs),
          const SizedBox(height: 14),
          _buildScoreCard(context, cs),
          const SizedBox(height: 14),
          _buildTimeCard(context, cs),
          const SizedBox(height: 14),
          _buildCertCard(context, cs),
          const SizedBox(height: 14),
          _buildStatusCard(context, cs),
          const SizedBox(height: 110),
        ],
      ),
    );
  }

  // ---------------- 卡片 1：抓包拦截 ----------------

  Widget _buildCaptureCard(BuildContext context, ColorScheme cs) {
    final port = context.watch<SettingsService>().capturePort;
    return AppCard(
      key: _kCapture,
      radius: 18,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Text('抓包拦截', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              ValueListenableBuilder<CaptureStatus>(
                valueListenable: CaptureEngine.I.status,
                builder: (_, s, _) =>
                    Switch(value: s.running, onChanged: _toggleEngine),
              ),
            ],
          ),
          ValueListenableBuilder<CaptureStatus>(
            valueListenable: CaptureEngine.I.status,
            builder: (_, s, _) => Text(
              s.running
                  ? (s.error.isEmpty
                        ? '监听中 127.0.0.1:${s.port} · 已改写 ${s.rewritten} 条'
                        : s.error)
                  : '开启后本机流量经内置代理转发，按下方规则自动改写成绩/完成时间',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: cs.outline),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('监听端口'),
              const SizedBox(width: 12),
              SizedBox(
                width: 110,
                child: TextField(
                  keyboardType: TextInputType.number,
                  controller: _portCtrl,
                  decoration: InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  style: const TextStyle(fontSize: 13),
                  onChanged: (v) {
                    final p = int.tryParse(v.trim());
                    if (p == null || p == port) return;
                    context.read<SettingsService>().setCapturePort(p);
                    // 端口改了必须让引擎换端口，否则代理指向新端口却没人监听
                    if (CaptureEngine.I.status.value.running) {
                      _restartEngineOnPort(p);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              if (CaptureSystem.isWindows) ...[
                SizedBox(
                  width: 300,
                  child: SegmentedButton<ProxyMode>(
                    segments: const [
                      ButtonSegment(
                        value: ProxyMode.pac,
                        label: Text('仅 E听说'),
                        icon: Icon(Icons.filter_alt_outlined, size: 15),
                      ),
                      ButtonSegment(
                        value: ProxyMode.system,
                        label: Text('全流量'),
                        icon: Icon(Icons.public, size: 15),
                      ),
                    ],
                    selected: {proxyMode},
                    onSelectionChanged: (sel) async {
                      final m = sel.first;
                      final wasSet = proxySet;
                      if (wasSet) await _restoreProxy(); // 先还原再换模式
                      await CaptureSystem.setProxyMode(m);
                      if (mounted) setState(() => proxyMode = m);
                      if (wasSet) await _setProxy(); // 原开着就按新模式重开
                    },
                  ),
                ),
                const SizedBox(width: 12),
              ],
              ValueListenableBuilder<CaptureStatus>(
                valueListenable: CaptureEngine.I.status,
                builder: (_, s, _) => FilterChip(
                  selected: proxySet,
                  label: Text(proxySet ? '已接管' : '设置代理'),
                  onSelected: (_) => proxySet ? _restoreProxy() : _setProxy(),
                ),
              ),
            ],
          ),
          if (proxySet)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                CaptureSystem.isWindows
                    ? (proxyMode == ProxyMode.pac
                          ? '仅 E听说 系域名走引擎，其余直连（不影响上网）。若 E听说 开着，重启一次它才会走代理。'
                          : '已接管 Windows 全局代理：所有流量都进引擎，兼容性最好但可能影响个别网站（原值已备份）。若 E听说 开着，重启一次它才会走代理。')
                    : '已设置安卓全局代理（需 Root）。若 E听说 开着，重启一次它才会走代理。',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: cs.outline),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------- 卡片 2：成绩 ----------------

  Widget _buildScoreCard(BuildContext context, ColorScheme cs) {
    final sec = context.watch<SettingsService>();
    final advanced = sec.captureAdvancedOn;
    return AppCard(
      key: _kScore,
      radius: 18,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.military_tech_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '修改指定成绩',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Switch(
                value: sec.captureScoreOn,
                onChanged: (v) {
                  context.read<SettingsService>().setCaptureScore(on: v);
                  setState(() {});
                },
              ),
            ],
          ),
          SizedBox(
            height: 42,
            child: TextField(
              controller: _scoreCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                isDense: true,
                labelText: '目标总成绩（分），例如：60（可超过满分）',
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: (v) =>
                  context.read<SettingsService>().setCaptureScore(value: v),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              FilterChip(
                selected: advanced,
                label: const Text('高级模式'),
                onSelected: (v) {
                  context.read<SettingsService>().setCaptureAdvanced(on: v);
                  setState(() {});
                },
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '按题型精确指定每小题得分',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: cs.outline),
                ),
              ),
            ],
          ),
          if (advanced) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                for (final cat in kCaptureCategoryLabels.keys) ...[
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: TextField(
                        controller: _catCtrls[cat],
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                        ],
                        decoration: InputDecoration(
                          isDense: true,
                          labelText:
                              '${kCaptureCategoryLabels[cat]}（${kDefaultCategoryMarks[cat] ?? '?'} 分）',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        style: const TextStyle(fontSize: 13),
                        onChanged: (_) => _saveCategoryScores(),
                      ),
                    ),
                  ),
                  if (cat != kCaptureCategoryLabels.keys.last)
                    const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '填了的题型直接按所填分提交；没填的题型按目标总成绩÷作业满分比例分摊。',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: cs.outline),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------- 卡片 3：完成时间 ----------------

  Widget _buildTimeCard(BuildContext context, ColorScheme cs) {
    final sec = context.watch<SettingsService>();
    return AppCard(
      key: _kTime,
      radius: 18,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.timer_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '修改完成时间',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Switch(
                value: sec.captureTimeOn,
                onChanged: (v) {
                  context.read<SettingsService>().setCaptureTime(on: v);
                  setState(() {});
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: TextField(
                      controller: _timeCtrls[i],
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: const ['天', '时', '分', '秒'][i],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      style: const TextStyle(fontSize: 13),
                      onChanged: (_) {
                        context.read<SettingsService>().setCaptureTime(
                          sec: _timeSec,
                        );
                        setState(() {});
                      },
                      // 空 = 不改；0 = 按提交时刻上传（0 秒偏移）
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Builder(
            builder: (_) {
              final t = _timeSec;
              final text = t < 0
                  ? '全空 = 不修改完成时间（直接放行）'
                  : (t == 0
                        ? '按提交时刻上传（0 秒偏移）'
                        : '完成时刻将提前 ${_durationEcho(t)}'
                              '（看起来是 $_durationEcho(t) 之前完成的）');
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: cs.outline),
                  ),
                  Text(
                    '接口只上报完成时刻（client_time）；所填时长由后台自动换算为完成时刻偏移，生效与否以实测为准。',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: cs.outline),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ---------------- 卡片 4：证书 ----------------

  Widget _buildCertCard(BuildContext context, ColorScheme cs) {
    return AppCard(
      radius: 18,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_outlined, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Text('HTTPS 证书', style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '拦截 HTTPS 需要设备信任软件生成的根证书：\n'
            '• Windows：点「一键安装证书」装进当前用户根证书库（免管理员）\n'
            '• Android（Root）：导出后装到系统证书分区（与装抓包工具证书同操作）',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: cs.outline, height: 1.5),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (CaptureSystem.isWindows) ...[
                FilledButton.tonalIcon(
                  onPressed: _installCa,
                  icon: const Icon(Icons.key_rounded),
                  label: const Text('一键安装证书'),
                ),
                if (caInstalled != null)
                  Text(
                    caInstalled! ? '已安装 ✓' : '未安装',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: cs.outline),
                  ),
              ],
              OutlinedButton.icon(
                onPressed: _exportCa,
                icon: const Icon(Icons.file_download_outlined),
                label: Text(CaptureSystem.isWindows ? '导出证书' : '导出证书（安卓用）'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------- 卡片 5：运行状态 ----------------

  /// 拦截链路是否就绪（引擎运行 + 证书可信 + 代理指向引擎）
  ({bool ready, String headline, List<String> checks}) _readiness(
    CaptureStatus s,
  ) {
    final sec = SettingsService.I;
    final checks = <String>[];
    checks.add(s.running ? '✓ 引擎运行中 127.0.0.1:${s.port}' : '✗ 引擎未运行');
    if (CaptureSystem.isWindows) {
      checks.add(
        caInstalled == true ? '✓ 证书已安装到当前用户受信任的根证书库' : '✗ 证书未安装（点上方「一键安装证书」）',
      );
    } else {
      checks.add('• 证书需手动装入系统分区（见上方证书卡），系统无法自动检测');
    }
    // 代理端口 ≠ 引擎监听端口 = 整机断网（历史故障），单独红字提示
    if (proxyPort != null && s.running && proxyPort != s.port) {
      checks.add(
        '✗✗ 代理指向 $proxyPort 端口，引擎却在 ${s.port} 监听 —— '
        '流量打不通，请关掉总开关再重新打开',
      );
    }
    checks.add(proxySet ? '✓ 系统代理已指向引擎' : '✗ 系统代理未指向引擎（点上方「设置系统代理」）');
    // E听说 是否在跑：开了代理后必须重启它才会走代理
    if (etsRunning) {
      checks.add('⚠ E听说 正在运行 —— 若刚设的代理，必须把 E听说 完全退出重开才生效');
    } else {
      checks.add('✓ E听说 未在运行（现在启动就会走代理）');
    }
    // 规则状态：链路通了但规则没开 = 改了没效果
    final scoreRuleOn =
        sec.captureScoreOn && double.tryParse(sec.captureScore.trim()) != null;
    checks.add(
      scoreRuleOn
          ? '✓ 成绩规则：目标 ${sec.captureScore.trim()} 分'
          : '• 成绩规则未生效（成绩卡开关未开或目标分为空）',
    );
    checks.add(
      sec.captureTimeOn
          ? '✓ 完成时间规则已开（${sec.captureTimeSec < 0 ? '不改' : '提前 ${sec.captureTimeSec} 秒'}）'
          : '• 完成时间规则未开（时间卡开关未开）',
    );
    final ruleOn = scoreRuleOn || sec.captureTimeOn;
    final ready = s.running && proxySet && (caInstalled ?? true);
    final headline = !ready
        ? '还不能改分：链路未就绪（见下方逐项）'
        : (ruleOn ? '可以开始做作业：拦截链路已就绪' : '链路已就绪，但规则都没开：改了也不会生效');
    return (ready: ready, headline: headline, checks: checks);
  }

  Widget _buildStatusCard(BuildContext context, ColorScheme cs) {
    return AppCard(
      radius: 18,
      padding: const EdgeInsets.all(16),
      child: ValueListenableBuilder<CaptureStatus>(
        valueListenable: CaptureEngine.I.status,
        builder: (_, s, _) {
          final r = _readiness(s);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    s.running
                        ? Icons.monitor_heart_rounded
                        : Icons.info_outline_rounded,
                    size: 18,
                    color: s.running ? cs.primary : cs.outline,
                  ),
                  const SizedBox(width: 8),
                  Text('运行状态', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(width: 6),
                  Text(
                    kEngineBuild,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: cs.outline),
                  ),
                  const Spacer(),
                  Text(
                    s.running ? '运行中' : '已停止',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: s.running ? cs.primary : cs.outline),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 就绪结论：一眼看出现在能不能开始做题
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: (r.ready ? cs.primary : cs.error).withValues(
                    alpha: 0.10,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  r.headline,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (final c in r.checks)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    c,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: cs.outline),
                  ),
                ),
              const SizedBox(height: 6),
              if (s.running)
                Text(
                  '监听 127.0.0.1:${s.port} · 拦截 ${s.intercepted} · 已改写 ${s.rewritten} · 未改写 ${s.passed}',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: cs.outline),
                ),
              Text(
                '⚠ 设置系统代理前如果 E听说 已开着，必须把它完全退出重开，才会走代理；'
                '做作业时开着本页面即可看到拦截/改写计数。',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: cs.outline, height: 1.5),
              ),
              if (s.events.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '最近事件（新→旧）：',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: cs.outline),
                ),
                // 可滚动查看全部历史（最新在上），不截断
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 190),
                  child: Scrollbar(
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: s.events.length,
                      itemBuilder: (_, i) => Text(
                        s.events[i],
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: cs.outline, height: 1.4),
                      ),
                    ),
                  ),
                ),
              ],
              if (s.lastRewrite.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '最近改写：${s.lastRewrite}',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: cs.outline),
                  ),
                ),
              if (s.running && s.lastNote.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '最近传输：${s.lastNote}',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: cs.outline),
                  ),
                ),
              const SizedBox(height: 8),
              // 日志目录：完整排查用
              Row(
                children: [
                  Icon(Icons.article_outlined, size: 14, color: cs.outline),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '日志：${CaptureLog.hintPath}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: cs.outline),
                    ),
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: () => _openLogFolder(CaptureLog.hintPath),
                    child: const Text('打开'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
