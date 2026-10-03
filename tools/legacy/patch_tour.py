import io

def patch(path, pairs):
    s = io.open(path, encoding='utf-8').read()
    for old, new in pairs:
        assert old in s, f'{path}: missing {old[:60]!r}'
        s = s.replace(old, new, 1)
    io.open(path, 'w', encoding='utf-8').write(s)
    print('ok', path)

# 1) settings: tourRequested
patch('lib/services/settings_service.dart', [
    ('''  bool showDemoData = true;''',
     '''  bool showDemoData = true;

  bool get tourRequested => _sp.getBool('tourRequested') ?? false;

  void requestTour({bool value = true}) {
    _sp.setBool('tourRequested', value);
    notifyListeners();
  }'''),
])

# 2) homework page: 锚点 + 自动播放
patch('lib/pages/homework_page.dart', [
    ('''  // 多选管理
  bool _selectMode = false;
  final Set<String> _selectedKeys = {};''',
     '''  // 多选管理
  bool _selectMode = false;
  final Set<String> _selectedKeys = {};

  // 互动教程锚点
  final _kChips = GlobalKey();
  final _kSearch = GlobalKey();'''),
    ('''    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ds = EtsDataService.I;
      if (ds.entries.isEmpty && !ds.scanning) ds.rescan();
    });''',
     '''    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ds = EtsDataService.I;
      if (ds.entries.isEmpty && !ds.scanning) ds.rescan();
      final s = SettingsService.I;
      if (s.tourRequested) {
        s.requestTour(value: false);
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _startTour());
      }
    });'''),
    ('''                      SizedBox(
                        height: 44,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _filterChip(''',
     '''                      SizedBox(
                        key: _kChips,
                        height: 44,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _filterChip('''),
    ('''                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _search,''',
     '''                      Row(
                        key: _kSearch,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _search,'''),
    ('''  void _toast(String msg) {''',
     '''  void _startTour() {
    if (!mounted) return;
    InteractiveTour.show(context, const [
      TourStep(
          null,
          '按类型筛选',
          '这里按题型筛选：全部 / 单词跟读 / 三问五答… 括号里是文件夹数量。'),
      TourStep(null, '搜索 · 排序 · 视图',
          '搜索标题或题号；排序支持时间正倒序与标题；视图可切列表 / 两列 / 三列网格。'),
      TourStep(null, '作业卡片',
          '长按卡片进入多选：全选、标记完成（收纳到「已完成区」）、删除（可恢复）。卡片右上 ✓ 即为完成。'),
      TourStep(null, '右下角按钮',
          '下拉后出现「回到顶部」；「重新扫描」会重新读取 E听说 作业数据。'),
    ]);
  }

  void _toast(String msg) {'''),
    ("import '../widgets/glass.dart';",
     "import '../widgets/glass.dart';\nimport '../widgets/interactive_tour.dart';"),
])

# 3) settings 关于：互动教程按钮
patch('lib/pages/settings_page.dart', [
    ('''                  icon: const Icon(Icons.school_rounded),
                  label: const Text('新手教程'),
                ),''',
     '''                  icon: const Icon(Icons.school_rounded),
                  label: const Text('新手教程'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    // 回到主界面，切到作业页后自动播放页面内互动教程
                    SettingsService.I.requestTour(value: true);
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                  icon: const Icon(Icons.tips_and_updates_rounded),
                  label: const Text('互动教程'),
                ),'''),
])

# 4) 开局教程结束后接着播放互动教程
patch('lib/pages/intro/onboarding_page.dart', [
    ('''    if (!widget.embedded) {
      SettingsService.I.finishOnboarding();
      await EtsDataService.I.rescan();
    }''',
     '''    if (!widget.embedded) {
      SettingsService.I.finishOnboarding();
      SettingsService.I.requestTour(value: true); // 接着播放页面内互动教程
      await EtsDataService.I.rescan();
    }'''),
])
print('tour wiring done')
