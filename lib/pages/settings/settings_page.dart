import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/extract_walkthrough.dart';

import '../../services/ai_service.dart';
import '../../services/ets_data_service.dart';
import '../../services/settings_service.dart';
import 'onboarding_page.dart';
import '../../services/extract_service.dart';
import '../../services/shell_service.dart';
import '../../services/update_service.dart';
import '../../widgets/color_picker_dialog.dart';
import '../../widgets/glass.dart';
import '../../widgets/style.dart';
import '../../widgets/tour_guide.dart';
import '../../widgets/sheet_picker.dart';

/// 设置页：外观 / AI 提供商与模型 / 数据目录 / 关于
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _testing = false;
  String _testResult = '';
  bool _checkingUpdate = false;
  String _updateText = '';
  String? _updateUrl; // 有新版时给「去下载」用
  // 分区导航
  final _scroll = ScrollController();
  final _kAppearance = GlobalKey();
  final _kAi = GlobalKey();
  final _kData = GlobalKey();
  final _kAbout = GlobalKey();
  String? _prov;
  String? _city;

  void _jumpTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    final cs = Theme.of(context).colorScheme;

    return GlassScaffold(
      body: Column(
        children: [
          // ---- 分区导航栏 ----
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                if (MediaQuery.of(context).size.width >= 700)
                  Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: Text(
                      '设置',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _navChip(context, '外观', _kAppearance),
                        _navChip(context, 'AI 配置', _kAi),
                        _navChip(context, '数据目录', _kData),
                        _navChip(context, '关于', _kAbout),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: _scroll,
              // 底部留出系统导航栏安全区，滚到最后一项不被盖住
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.viewPaddingOf(context).bottom,
              ),
              children: [
                // ---- 使用帮助（置顶，避免新手找不到） ----
                AppCard(
                  radius: 18,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _cardTitle(context, '使用帮助', Icons.help_outline_rounded),
                      const SizedBox(height: 8),
                      Text(
                        '按功能查看图文引导：作业列表、AI 对话、修改、'
                        '作业详情页都有对应说明。',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: cs.outline),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 44,
                              child: FilledButton.icon(
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const OnboardingPage(embedded: true),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.school_rounded,
                                  size: 18,
                                ),
                                label: const Text('新手教程'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SizedBox(
                              height: 44,
                              child: OutlinedButton.icon(
                                onPressed: () => TourHub.showHelpSheet(context),
                                icon: const Icon(Icons.map_outlined, size: 18),
                                label: const Text('功能引导'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ---- 外观 ----
                AppCard(
                  key: _kAppearance,
                  radius: 18,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _cardTitle(context, '外观', Icons.palette_outlined),
                      const SizedBox(height: 10),
                      SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.system,
                            label: Text('跟随系统'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            label: Text('浅色'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            label: Text('深色'),
                          ),
                        ],
                        selected: {s.themeMode},
                        onSelectionChanged: (sel) => s.setThemeMode(sel.first),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '软件风格',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: cs.outline),
                      ),
                      const SizedBox(height: 6),
                      SegmentedButton<AppStyle>(
                        segments: const [
                          ButtonSegment(
                            value: AppStyle.material,
                            label: Text('默认风格'),
                          ),
                          ButtonSegment(
                            value: AppStyle.glass,
                            label: Text('液态玻璃'),
                          ),
                        ],
                        selected: {s.styleMode},
                        onSelectionChanged: (sel) => s.setStyleMode(sel.first),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '布局（平板左侧菜单 / 手机底部菜单）',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: cs.outline),
                      ),
                      const SizedBox(height: 6),
                      SegmentedButton<UiLayoutMode>(
                        segments: const [
                          ButtonSegment(
                            value: UiLayoutMode.auto,
                            label: Text('自动'),
                          ),
                          ButtonSegment(
                            value: UiLayoutMode.tablet,
                            label: Text('平板/电脑'),
                          ),
                          ButtonSegment(
                            value: UiLayoutMode.mobile,
                            label: Text('手机'),
                          ),
                        ],
                        selected: {s.layoutMode},
                        onSelectionChanged: (sel) => s.setLayoutMode(sel.first),
                      ),
                      const SizedBox(height: 4),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '跟读高亮',
                          style: TextStyle(fontSize: 13),
                        ),
                        subtitle: const Text(
                          '播放时逐句染色：读过的句子与当前句高亮',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: s.followHighlight,
                        onChanged: (v) => s.setFollowHighlight(v),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '主题颜色',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: cs.outline),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final c in const [
                            0xFF4F6BFF,
                            0xFF6750A4,
                            0xFF00696E,
                            0xFF2E6B27,
                            0xFF8A4F00,
                            0xFFB3261E,
                            0xFF984061,
                            0xFFE91E8C, // 粉色
                          ])
                            _colorDot(context, c),
                        ],
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => _openColorPicker(context),
                        icon: const Icon(Icons.colorize_rounded),
                        label: const Text('自定义颜色（打开调色板）'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ---- AI 配置 ----
                _AiSection(
                  key: _kAi,
                  testing: _testing,
                  testResult: _testResult,
                  onTest: _test,
                  onTestStateChanged: () => setState(() {}),
                ),
                const SizedBox(height: 14),

                // ---- 数据目录 ----
                AppCard(
                  key: _kData,
                  radius: 18,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _cardTitle(context, '数据目录', Icons.folder_outlined),
                      const SizedBox(height: 8),
                      if (Platform.isWindows)
                        Text(
                          '当前主目录：${s.activeRoots.firstOrNull ?? '（未设置）'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (Platform.isAndroid) ...[
                        Text(
                          'APP 数据目录：${s.androidRoot}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () async {
                                final messenger = ScaffoldMessenger.of(context);
                                final ok =
                                    await SettingsService.requestAndroidStorage();
                                if (!mounted) return;
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      ok ? '权限已授予，请点「刷新」' : '未授予权限',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.lock_open_rounded),
                              label: const Text('申请"所有文件访问"权限'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _openDataFolder(context, s.androidRoot),
                              icon: const Icon(Icons.folder_open_rounded),
                              label: const Text('打开数据目录'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const _AndroidExtractCard(),
                      ],
                      if (Platform.isWindows) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: _pickRoot,
                              icon: const Icon(
                                Icons.create_new_folder_outlined,
                              ),
                              label: const Text('添加其他数据目录'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _openDataFolder(
                                context,
                                s.activeRoots.firstOrNull ?? '',
                              ),
                              icon: const Icon(Icons.folder_open_rounded),
                              label: const Text('打开数据目录'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => ExtractService.refresh(),
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('刷新'),
                            ),
                          ],
                        ),
                      ],
                      for (final r in s.extraRoots)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.folder_special_outlined),
                          title: Text(r, style: const TextStyle(fontSize: 13)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: '打开此目录',
                                icon: const Icon(Icons.folder_open_rounded),
                                onPressed: () => _openDataFolder(context, r),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded),
                                onPressed: () => s.removeExtraRoot(r),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ---- 考试信息（格式匹配：初中/高中、地区）----
                AppCard(
                  radius: 18,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _cardTitle(context, '考试信息（格式匹配）', Icons.school_outlined),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const SizedBox(
                            width: 56,
                            child: Text('年级', style: TextStyle(fontSize: 13)),
                          ),
                          Expanded(
                            child: SheetPickerField(
                              label: s.grade.isEmpty ? '选择年级' : s.grade,
                              placeholder: '选择年级',
                              onTap: () async {
                                final v = await showSheetPicker<String>(
                                  context,
                                  title: '选择年级',
                                  current: s.grade.isEmpty ? null : s.grade,
                                  options: [
                                    for (final g in [
                                      '初一',
                                      '初二',
                                      '初三',
                                      '高一',
                                      '高二',
                                      '高三',
                                    ])
                                      (g, g),
                                  ],
                                );
                                if (v != null) s.setExamInfo(grade: v);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const SizedBox(
                            width: 56,
                            child: Text('省份', style: TextStyle(fontSize: 13)),
                          ),
                          Expanded(
                            child: SheetPickerField(
                              label: _prov ?? '选择省份',
                              placeholder: '选择省份',
                              onTap: () async {
                                final v = await showSheetPicker<String>(
                                  context,
                                  title: '选择省份',
                                  current: _prov,
                                  searchHint: '搜索省份',
                                  options: [
                                    for (final prov in kRegionMap.keys)
                                      (prov, prov),
                                  ],
                                );
                                if (v == null) return;
                                setState(() {
                                  _prov = v;
                                  _city = null;
                                });
                                final city = kRegionMap[v]!.first;
                                s.setExamInfo(region: v + city);
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SheetPickerField(
                              label: _city ?? (_prov == null ? '先选省份' : '选择城市'),
                              placeholder: '选择城市',
                              enabled: _prov != null,
                              onTap: _prov == null
                                  ? null
                                  : () async {
                                      final v = await showSheetPicker<String>(
                                        context,
                                        title: '选择城市',
                                        current: _city,
                                        searchHint: '搜索城市',
                                        options: [
                                          // '' 哨兵 = 未选择（与取消区分开）
                                          ('', '未选择'),
                                          for (final c in kRegionMap[_prov]!)
                                            (c, c),
                                        ],
                                      );
                                      if (v == null) return;
                                      setState(
                                        () => _city = v.isEmpty ? null : v,
                                      );
                                      s.setExamInfo(region: _prov! + v);
                                    },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const SizedBox(height: 6),
                      Text(
                        '年级决定初中/高中格式匹配；批量生成标题也会参考年级与地区。',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: cs.outline),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ---- 关于 ----
                AppCard(
                  key: _kAbout,
                  radius: 18,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _cardTitle(context, '关于', Icons.info_outline_rounded),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: Image.asset(
                              'assets/TX.png',
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => CircleAvatar(
                                radius: 28,
                                child: Text(
                                  'K',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '苦力怕.KULIPA',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  'E听说助手 作者',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: cs.outline),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            'E听说助手',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(width: 8),
                          // 版本徽章（对外版本号固定 0.8，见 kAppVersion）
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              'V$kAppVersion',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '本地解析 E听说 客户端已下载的作业数据（content_*/template_*），'
                        '不联网上传任何数据；AI 调用仅在配置后由用户主动触发。'
                        '仅供学习研究使用。',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: cs.outline, height: 1.5),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => launchUrl(
                            Uri.parse(kGithubRepoUrl),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.code_rounded, size: 18),
                          label: const Text('GitHub 开源仓库 · ETS-TOOLS'),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        kGithubRepoLabel,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: cs.primary),
                      ),
                      const SizedBox(height: 12),
                      // ---- 检查更新 ----
                      Row(
                        children: [
                          SizedBox(
                            height: 40,
                            child: FilledButton.tonalIcon(
                              onPressed: _checkingUpdate ? null : _checkUpdate,
                              icon: _checkingUpdate
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.system_update_alt_rounded,
                                      size: 18,
                                    ),
                              label: const Text('检查更新'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _updateText,
                              style: TextStyle(
                                fontSize: 12,
                                color: _updateText.startsWith('✗')
                                    ? cs.error
                                    : _updateText.startsWith('✓')
                                    ? Colors.green
                                    : cs.outline,
                              ),
                            ),
                          ),
                          if (_updateUrl != null)
                            TextButton(
                              onPressed: () => launchUrl(
                                Uri.parse(_updateUrl!),
                                mode: LaunchMode.externalApplication,
                              ),
                              child: const Text(
                                '去下载',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '启动时自动检测更新',
                          style: TextStyle(fontSize: 13),
                        ),
                        subtitle: const Text(
                          '每次打开软件向官网查一次版本号，有新版本会提示「去下载」',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: s.autoCheckUpdate,
                        onChanged: (v) => s.setAutoCheckUpdate(v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 110),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navChip(BuildContext context, String label, GlobalKey key) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        avatar: Icon(
          Icons.bookmark_border_rounded,
          size: 14,
          color: cs.primary,
        ),
        visualDensity: VisualDensity.compact,
        onPressed: () => _jumpTo(key),
      ),
    );
  }

  Future<void> _openColorPicker(BuildContext context) async {
    final s = context.read<SettingsService>();
    final picked = await showDialog<Color>(
      context: context,
      builder: (context) => ColorPickerDialog(initial: Color(s.accentValue)),
    );
    if (picked != null) {
      s.setAccent(picked.toARGB32(), custom: true);
    }
  }

  Widget _colorDot(BuildContext context, int color) {
    final s = context.watch<SettingsService>();
    final selected = !s.useCustomColor && s.accentValue == color;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => s.setAccent(color, custom: false),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Color(color),
          shape: BoxShape.circle,
          border: selected
              ? Border.all(
                  width: 3,
                  color: Theme.of(context).colorScheme.primary,
                )
              : null,
        ),
        child: selected
            ? const Icon(Icons.check, color: Colors.white, size: 18)
            : null,
      ),
    );
  }

  Future<void> _pickRoot() async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择 ETS 数据目录',
    );
    if (dir != null) {
      SettingsService.I.addExtraRoot(dir);
      EtsDataService.I.rescan();
    }
  }

  /// 用系统文件管理器打开数据目录（安卓失败时兜底复制路径）
  Future<void> _openDataFolder(BuildContext context, String path) async {
    final messenger = ScaffoldMessenger.of(context);
    if (path.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('未设置数据目录')));
      return;
    }
    if (Platform.isWindows) {
      if (!Directory(path).existsSync()) {
        messenger.showSnackBar(SnackBar(content: Text('目录不存在：$path')));
        return;
      }
      await Process.run('explorer', [path]);
      return;
    }
    if (Platform.isAndroid) {
      final r = await ShellService.exec(
        'am start -a android.intent.action.VIEW -d "file://$path"',
      );
      if (r != null && r.exit == 0) return;
      await Clipboard.setData(ClipboardData(text: path));
      messenger.showSnackBar(SnackBar(content: Text('无法直接打开，已复制路径：$path')));
    }
  }

  /// 手动检查更新（启动时那次是静默的，见 HomeShell._autoCheckUpdate）
  Future<void> _checkUpdate() async {
    setState(() {
      _checkingUpdate = true;
      _updateText = '';
      _updateUrl = null;
    });
    final r = await UpdateService.I.check();
    if (!mounted) return;
    setState(() {
      _checkingUpdate = false;
      switch (r.status) {
        case UpdateStatus.newer:
          _updateText = '✓ 发现新版本 V${r.remote?.version}（当前 V${r.localVersion}）';
          _updateUrl = r.remote?.url;
        case UpdateStatus.upToDate:
          _updateText = '✓ 已是最新（V${r.localVersion}）';
        case UpdateStatus.failed:
          _updateText = '✗ 检查失败：${r.error ?? '未知原因'}';
      }
    });
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = '';
    });
    try {
      final r = await AiService.I.testConnection();
      _testResult = '✓ $r';
    } catch (e) {
      _testResult = '✗ $e';
    }
    if (mounted) setState(() => _testing = false);
  }
}

Widget _cardTitle(BuildContext context, String title, IconData icon) {
  final cs = Theme.of(context).colorScheme;
  return Row(
    children: [
      Icon(icon, size: 18, color: cs.primary),
      const SizedBox(width: 6),
      Text(title, style: Theme.of(context).textTheme.titleSmall),
    ],
  );
}

/// AI 提供商 / 模型管理
class _AiSection extends StatefulWidget {
  final bool testing;
  final String testResult;
  final VoidCallback onTest;
  final VoidCallback onTestStateChanged;

  const _AiSection({
    super.key,
    required this.testing,
    required this.testResult,
    required this.onTest,
    required this.onTestStateChanged,
  });

  @override
  State<_AiSection> createState() => _AiSectionState();
}

class _AiSectionState extends State<_AiSection> {
  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    final cs = Theme.of(context).colorScheme;

    return AppCard(
      radius: 18,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(context, 'AI 配置（多提供商 / 多模型）', Icons.auto_awesome),
          const SizedBox(height: 8),
          // Agnes 免费领取提示
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.card_giftcard_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Agnes 完全免费 · 不限额度。登录官网即可免费领取 API Key',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(height: 1.4),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(kAgnesLoginUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 14),
                  label: const Text('免费领取', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 提供商列表
          for (final pr in s.providers)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.dns_rounded, size: 16, color: cs.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          pr.name,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        tooltip: '删除提供商',
                        iconSize: 18,
                        onPressed: () => s.removeProvider(pr.id),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                  _aiField(
                    context,
                    '名称',
                    pr.name,
                    onChanged: (v) => s.updateProvider(
                      AiProvider(
                        id: pr.id,
                        name: v,
                        baseUrl: pr.baseUrl,
                        apiKey: pr.apiKey,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _aiField(
                    context,
                    '接口地址 Base URL',
                    pr.baseUrl,
                    onChanged: (v) => s.updateProvider(
                      AiProvider(
                        id: pr.id,
                        name: pr.name,
                        baseUrl: v,
                        apiKey: pr.apiKey,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _aiField(
                    context,
                    'API Key',
                    pr.apiKey,
                    obscure: true,
                    onChanged: (v) => s.updateProvider(
                      AiProvider(
                        id: pr.id,
                        name: pr.name,
                        baseUrl: pr.baseUrl,
                        apiKey: v,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: ActionChip(
              avatar: const Icon(Icons.add_rounded, size: 16),
              label: const Text('添加提供商'),
              onPressed: () => _addProvider(context),
            ),
          ),
          const Divider(height: 24),

          // 模型列表：按提供商归类，顺序 = 调用优先级（故障切换顺序）
          if (s.models.isEmpty)
            Text(
              '尚未添加模型 · AI 功能不可用（提供商可以没有模型）',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: cs.outline),
            ),
          for (final pr in s.providers) ..._providerModels(context, s, pr),
          Align(
            alignment: Alignment.centerLeft,
            child: ActionChip(
              avatar: const Icon(Icons.add_rounded, size: 16),
              label: const Text('添加模型'),
              onPressed: () => _addModel(context),
            ),
          ),
          const Divider(height: 24),

          const SizedBox(height: 12),

          // 测试
          Row(
            children: [
              SizedBox(
                height: 44,
                child: FilledButton.tonalIcon(
                  onPressed: widget.testing ? null : widget.onTest,
                  icon: widget.testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering_rounded),
                  label: const Text('测试连接（当前模型）'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.testResult,
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.testResult.startsWith('✓')
                        ? Colors.green
                        : cs.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '兼容任意 OpenAI 兼容接口（DeepSeek / 智谱 GLM / Kimi / 通义 / OpenAI / 本地 Ollama 等）。'
            '"思考"开启后：档位「开」请求模型输出思考内容，低/中/高注入 reasoning_effort；'
            '若你的接口不支持导致报错，请关闭该模型思考。（Agnes 默认只启用「开」）',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: cs.outline),
          ),
        ],
      ),
    );
  }

  /// 某提供商下的模型组（顺序即调用优先级）
  List<Widget> _providerModels(
    BuildContext context,
    SettingsService s,
    AiProvider pr,
  ) {
    final cs = Theme.of(context).colorScheme;
    final ms = s.models.where((m) => m.providerId == pr.id).toList();
    if (ms.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Row(
          children: [
            Icon(Icons.model_training_rounded, size: 14, color: cs.primary),
            const SizedBox(width: 6),
            Text(
              '${pr.name} · 模型（顺序 = 调用优先级）',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
      ),
      for (var i = 0; i < ms.length; i++)
        Container(
          margin: const EdgeInsets.only(bottom: 8, left: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: s.currentModelId == ms[i].id
                ? cs.primaryContainer.withValues(alpha: 0.4)
                : cs.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: '设为首选模型',
                    iconSize: 18,
                    isSelected: s.currentModelId == ms[i].id,
                    onPressed: () => s.setCurrentModel(ms[i].id),
                    icon: Icon(
                      s.currentModelId == ms[i].id
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${i + 1}. ${ms[i].name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: '优先级上移',
                    iconSize: 18,
                    onPressed: i > 0 ? () => s.moveModel(ms[i].id, -1) : null,
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                  IconButton(
                    tooltip: '优先级下移',
                    iconSize: 18,
                    onPressed: i < ms.length - 1
                        ? () => s.moveModel(ms[i].id, 1)
                        : null,
                    icon: const Icon(Icons.arrow_downward_rounded),
                  ),
                  IconButton(
                    tooltip: '编辑模型',
                    iconSize: 18,
                    onPressed: () => _editModel(context, ms[i]),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: '删除模型',
                    iconSize: 18,
                    onPressed: () => s.removeModel(ms[i].id),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 6, top: 6),
                child: Wrap(
                  alignment: WrapAlignment.start,
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilterChip(
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      selected: ms[i].thinking,
                      label: Text(
                        '思考${ms[i].thinking ? '·${kThinkingLevelLabels[ms[i].thinkingLevel] ?? ms[i].thinkingLevel}' : ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onSelected: (v) =>
                          s.updateModel(ms[i].copyWith(thinking: v)),
                    ),
                    // 档位菜单：已启用档位按配置顺序在前，其余标准档位跟在后面
                    //（选了没启用的会自动加进启用列表）
                    if (ms[i].thinking)
                      PopupMenuButton<String>(
                        tooltip: '思考级别',
                        onSelected: (v) => s.setThinkingOption(ms[i], v),
                        itemBuilder: (_) => [
                          for (final lv in s
                              .thinkingMenuLevels(ms[i])
                              .where((e) => e != 'off'))
                            PopupMenuItem(
                              value: lv,
                              child: Text(
                                '${kThinkingLevelLabels[lv] ?? lv} $lv',
                              ),
                            ),
                        ],
                        child: Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            kThinkingLevelLabels[ms[i].thinkingLevel] ??
                                ms[i].thinkingLevel,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    FilterChip(
                      visualDensity: VisualDensity.compact,
                      selected: ms[i].multimodal,
                      label: const Text('多模态', style: TextStyle(fontSize: 12)),
                      onSelected: (v) =>
                          s.updateModel(ms[i].copyWith(multimodal: v)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _aiField(
    BuildContext context,
    String label,
    String value, {
    required ValueChanged<String> onChanged,
    bool obscure = false,
  }) {
    return TextField(
      controller: TextEditingController(text: value)
        ..selection = TextSelection.collapsed(offset: value.length),
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      style: const TextStyle(fontSize: 13),
      onChanged: onChanged,
    );
  }

  Future<void> _addProvider(BuildContext context) async {
    final s = context.read<SettingsService>();
    final name = TextEditingController();
    final url = TextEditingController();
    final key = TextEditingController();
    String? preset; // 预设选择

    await showDialog(
      context: context,
      // 表单较长（且带思考档位排序列表），包滚动避免键盘弹起时溢出
      builder: (context) => SingleChildScrollView(
        child: StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: const Text('添加 AI 提供商'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SheetPickerField(
                  label: preset == null
                      ? '从预设选择'
                      : (preset == 'custom'
                            ? '自定义'
                            : kAiProviderPresets
                                  .firstWhere((e) => e.$2 == preset)
                                  .$1),
                  placeholder: '从预设选择',
                  onTap: () async {
                    final v = await showSheetPicker<String>(
                      context,
                      title: '从预设选择',
                      current: preset,
                      addInset: true,
                      options: [
                        for (final (n, u) in kAiProviderPresets) (u, n),
                        const ('custom', '自定义'),
                      ],
                    );
                    if (v == null) return;
                    setDialog(() {
                      preset = v;
                      if (v != 'custom') {
                        name.text = kAiProviderPresets
                            .firstWhere((e) => e.$2 == v)
                            .$1;
                        url.text = v;
                      }
                    });
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: '名称',
                    hintText: 'DeepSeek / Agnes / 自定义',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: url,
                  decoration: const InputDecoration(
                    labelText: '接口地址（OpenAI 兼容）',
                    hintText: 'https://api.agnes-ai.cn/v1',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: key,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'API Key'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () async {
                  final baseUrl = url.text.trim();
                  if (name.text.trim().isEmpty || baseUrl.isEmpty) return;
                  // 自动检测相同 API 地址 → 提示是否归类到已有提供商
                  final existing = s.providers.firstWhere(
                    (e) =>
                        e.baseUrl.replaceAll(RegExp(r'/+$'), '') ==
                        baseUrl.replaceAll(RegExp(r'/+$'), ''),
                    orElse: () =>
                        AiProvider(id: '', name: '', baseUrl: '', apiKey: ''),
                  );
                  Navigator.pop(context);
                  if (existing.id.isNotEmpty) {
                    final merge = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('检测到相同 API 地址'),
                        content: Text(
                          '「${existing.name}」已使用该接口地址。\n\n'
                          '是否把要添加的模型归类到该提供商下？（提供商不会重复创建）',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('仍要新建'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('自动归类'),
                          ),
                        ],
                      ),
                    );
                    if (merge == true) {
                      widget.onTestStateChanged();
                      if (context.mounted) {
                        await _addModel(context, existing); // 直接在该提供商下加模型
                      }
                      return;
                    }
                  }
                  s.addProvider(
                    AiProvider(
                      id: 'p${DateTime.now().millisecondsSinceEpoch}',
                      name: name.text.trim(),
                      baseUrl: baseUrl,
                      apiKey: key.text.trim(),
                    ),
                  );
                  widget.onTestStateChanged();
                },
                child: const Text('添加'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 思考档位编辑器：已启用档位可拖动排序/移除，未启用的点chip添加
  /// （对所有模型开放；Agnes 默认只勾了「开」，要低/中/高在这里加）
  List<Widget> _levelEditor(
    void Function(void Function()) setDialog,
    List<String> levels,
  ) {
    const all = kThinkingLevelOrder;
    final remaining = all.where((e) => !levels.contains(e)).toList();
    final cs = Theme.of(context).colorScheme;
    return [
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '思考档位（对话页按此顺序显示）',
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ),
      const SizedBox(height: 4),
      // 关：始终可用，由"思考"开关承担，不参与排序
      ListTile(
        dense: true,
        enabled: false,
        title: const Text('关', style: TextStyle(fontSize: 13)),
        subtitle: const Text('始终可用（思考开关关闭即选中）', style: TextStyle(fontSize: 12)),
        trailing: const SizedBox(width: 40, height: 1),
      ),
      if (levels.isEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '未启用任何档位，对话页将只能选「关」',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: cs.outline),
          ),
        ),
      ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: true,
        // onReorderItem 的 newIndex 已自动修正移除项偏移
        onReorderItem: (oldI, newI) => setDialog(() {
          levels.insert(newI.clamp(0, levels.length), levels.removeAt(oldI));
        }),
        children: [
          for (var i = 0; i < levels.length; i++)
            ListTile(
              key: ValueKey(levels[i]),
              dense: true,
              title: Text(
                kThinkingLevelLabels[levels[i]] ?? levels[i],
                style: const TextStyle(fontSize: 13),
              ),
              trailing: IconButton(
                tooltip: '移除',
                icon: const Icon(Icons.close_rounded, size: 16),
                onPressed: levels.length <= 1
                    ? null // 至少保留一档，避免菜单退化
                    : () => setDialog(() => levels.removeAt(i)),
              ),
            ),
        ],
      ),
      if (remaining.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final lv in remaining)
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.add_rounded, size: 14),
                  label: Text(
                    kThinkingLevelLabels[lv] ?? lv,
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () => setDialog(() => levels.add(lv)),
                ),
            ],
          ),
        ),
    ];
  }

  Future<void> _addModel(
    BuildContext context, [
    AiProvider? presetProvider,
  ]) async {
    final s = context.read<SettingsService>();
    if (s.providers.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先添加提供商')));
      return;
    }
    var providerId = presetProvider?.id ?? s.providers.first.id;
    final name = TextEditingController();
    final model = TextEditingController();
    final maxContextCtrl = TextEditingController();
    final maxOutputCtrl = TextEditingController();
    final retriesCtrl = TextEditingController();
    final rateCtrl = TextEditingController();
    var thinking = false;
    // Agnes 默认只给「开」一档（它只支持开关思考）；其他提供商默认三档
    var levels = s.isAgnesProvider(providerId)
        ? <String>['on']
        : <String>['low', 'medium', 'high'];
    var multimodal = true; // 默认勾选图片多模态

    await showDialog(
      context: context,
      // 表单较长（且带思考档位排序列表），包滚动避免键盘弹起时溢出
      builder: (context) => SingleChildScrollView(
        child: StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: const Text('添加模型'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SheetPickerField(
                    label:
                        s.providers
                            .where((e) => e.id == providerId)
                            .map((e) => e.name)
                            .firstOrNull ??
                        '选择提供商',
                    placeholder: '选择提供商',
                    onTap: () async {
                      final v = await showSheetPicker<String>(
                        context,
                        title: '所属提供商',
                        current: providerId,
                        addInset: true,
                        options: [
                          for (final pr in s.providers) (pr.id, pr.name),
                        ],
                      );
                      if (v == null) return;
                      setDialog(() => providerId = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: '显示名',
                      hintText: 'GLM-4.6',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: model,
                    decoration: const InputDecoration(
                      labelText: '模型 ID',
                      hintText: 'glm-4.6',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: maxContextCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: '最大上下文（tokens）',
                            hintText: '留空 = 不裁剪',
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: maxOutputCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: '最大输出（tokens）',
                            hintText: '留空 = 4096',
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: retriesCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: '失败重试（本模型）',
                            hintText: '默认 5',
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: rateCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: '限速/分钟（本模型）',
                            hintText: '默认 5',
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      FilterChip(
                        selected: thinking,
                        label: const Text('思考'),
                        onSelected: (v) => setDialog(() => thinking = v),
                      ),
                      const Spacer(),
                      FilterChip(
                        selected: multimodal,
                        label: const Text('多模态'),
                        onSelected: (v) => setDialog(() => multimodal = v),
                      ),
                    ],
                  ),
                  // 档位编辑器对所有模型开放（Agnes 默认只勾「开」，要低/中/高自己加）
                  if (thinking) ..._levelEditor(setDialog, levels),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  if (name.text.trim().isNotEmpty &&
                      model.text.trim().isNotEmpty) {
                    s.addModel(
                      AiModel(
                        id: 'm${DateTime.now().millisecondsSinceEpoch}',
                        name: name.text.trim(),
                        model: model.text.trim(),
                        providerId: providerId,
                        thinking: thinking,
                        thinkingLevel: thinking
                            ? (levels.contains('medium')
                                  ? 'medium'
                                  : levels.firstOrNull ?? 'medium')
                            : 'medium',
                        multimodal: multimodal,
                        thinkingLevels: levels,
                        maxContext: int.tryParse(maxContextCtrl.text.trim()),
                        maxOutput: int.tryParse(maxOutputCtrl.text.trim()),
                        retries: int.tryParse(retriesCtrl.text.trim()) ?? 5,
                        ratePerMin: int.tryParse(rateCtrl.text.trim()) ?? 10,
                      ),
                    );
                    widget.onTestStateChanged();
                  }
                  Navigator.pop(context);
                },
                child: const Text('添加'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editModel(BuildContext context, AiModel m) async {
    final s = context.read<SettingsService>();
    final name = TextEditingController(text: m.name);
    final model = TextEditingController(text: m.model);
    final maxContextCtrl = TextEditingController(
      text: m.maxContext == null ? '' : '${m.maxContext}',
    );
    final maxOutputCtrl = TextEditingController(
      text: m.maxOutput == null ? '' : '${m.maxOutput}',
    );
    final retriesCtrl = TextEditingController(text: '${m.retries}');
    final rateCtrl = TextEditingController(text: '${m.ratePerMin}');
    var providerId = m.providerId;
    var thinking = m.thinking;
    var levels = List<String>.from(m.thinkingLevels);
    var multimodal = m.multimodal;

    await showDialog(
      context: context,
      // 表单较长（且带思考档位排序列表），包滚动避免键盘弹起时溢出
      builder: (context) => SingleChildScrollView(
        child: StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: const Text('编辑模型'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SheetPickerField(
                    label:
                        s.providers
                            .where((e) => e.id == providerId)
                            .map((e) => e.name)
                            .firstOrNull ??
                        '选择提供商',
                    placeholder: '选择提供商',
                    onTap: () async {
                      final v = await showSheetPicker<String>(
                        context,
                        title: '所属提供商',
                        current: providerId,
                        addInset: true,
                        options: [
                          for (final pr in s.providers) (pr.id, pr.name),
                        ],
                      );
                      if (v == null) return;
                      setDialog(() {
                        providerId = v;
                        // 切换到 Agnes：档位收窄为「开」
                        if (s.isAgnesProvider(v)) levels = ['on'];
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: '显示名'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: model,
                    decoration: const InputDecoration(labelText: '模型 ID'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: maxContextCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: '最大上下文（tokens）',
                            hintText: '留空 = 不裁剪',
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: maxOutputCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: '最大输出（tokens）',
                            hintText: '留空 = 4096',
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: retriesCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: '失败重试（本模型）',
                            hintText: '默认 5',
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: rateCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: '限速/分钟（本模型）',
                            hintText: '默认 5',
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      FilterChip(
                        selected: thinking,
                        label: const Text('思考'),
                        onSelected: (v) => setDialog(() => thinking = v),
                      ),
                      const Spacer(),
                      FilterChip(
                        selected: multimodal,
                        label: const Text('多模态'),
                        onSelected: (v) => setDialog(() => multimodal = v),
                      ),
                    ],
                  ),
                  // 档位编辑器对所有模型开放（含 Agnes）
                  if (thinking) ..._levelEditor(setDialog, levels),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  s.updateModel(
                    m.copyWith(
                      name: name.text.trim().isEmpty
                          ? m.name
                          : name.text.trim(),
                      model: model.text.trim().isEmpty
                          ? m.model
                          : model.text.trim(),
                      providerId: providerId,
                      thinking: thinking,
                      // 当前档位不在启用列表里时归位，避免菜单残留旧档位
                      thinkingLevel: levels.contains(m.thinkingLevel)
                          ? m.thinkingLevel
                          : (levels.isEmpty ? 'medium' : levels.first),
                      multimodal: multimodal,
                      thinkingLevels: levels,
                      maxContext: int.tryParse(maxContextCtrl.text.trim()),
                      maxOutput: int.tryParse(maxOutputCtrl.text.trim()),
                      retries: int.tryParse(retriesCtrl.text.trim()),
                      ratePerMin: int.tryParse(rateCtrl.text.trim()),
                    ),
                  );
                  Navigator.pop(context);
                },
                child: const Text('保存'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Android 提取卡片（Root/Shizuku）
class _AndroidExtractCard extends StatefulWidget {
  const _AndroidExtractCard();

  @override
  State<_AndroidExtractCard> createState() => _AndroidExtractCardState();
}

class _AndroidExtractCardState extends State<_AndroidExtractCard> {
  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.admin_panel_settings_rounded,
                size: 18,
                color: cs.primary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '数据提取（四种读取方式）',
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  SettingsService.I.resetAndroidRoot();
                  EtsDataService.I.rescan();
                },
                child: const Text('恢复默认路径'),
              ),
            ],
          ),
          Text(
            'Android 11+ 限制访问其他应用目录。Shizuku / Root / 直读 / SAF '
            '四种通道任选其一，提取一次即可长期使用；也可回「作业」页点「刷新」自动提取。',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: cs.outline, height: 1.4),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              SizedBox(
                width: 170,
                child: SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用 Root', style: TextStyle(fontSize: 13)),
                  value: s.useRoot,
                  onChanged: (v) {
                    s.setChannel(root: v);
                    setState(() {});
                  },
                ),
              ),
              SizedBox(
                width: 190,
                child: SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    '启用 Shizuku',
                    style: TextStyle(fontSize: 13),
                  ),
                  value: s.useShizuku,
                  onChanged: (v) {
                    s.setChannel(shizuku: v);
                    setState(() {});
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 四通道模式选择面板（与作业页空态同一个组件）
          ExtractWalkthrough(
            onExtract: (msg) async {
              await EtsDataService.I.rescan();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(msg)));
            },
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ActionChip(
                avatar: const Icon(Icons.download_rounded, size: 14),
                label: const Text(
                  '下载 Shizuku APK',
                  style: TextStyle(fontSize: 12),
                ),
                onPressed: () => launchUrl(
                  Uri.parse(kShizukuApkUrl),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.bolt_rounded, size: 14),
                label: const Text('镜像下载', style: TextStyle(fontSize: 12)),
                onPressed: () => launchUrl(
                  Uri.parse(kShizukuMirrorUrl),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
