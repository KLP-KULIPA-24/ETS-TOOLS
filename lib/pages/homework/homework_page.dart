import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/ets_models.dart';
import '../../services/ets_data_service.dart';
import '../../services/settings_service.dart';
import '../../services/extract_service.dart';
import '../../services/title_batch_service.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';
import '../../widgets/interactive_tour.dart';
import '../../widgets/tour_guide.dart';
import '../../widgets/extract_walkthrough.dart';
import '../detail/content_detail_page.dart';
import 'group_page.dart';
import '../../services/achievements.dart';

enum _SortMode { newest, oldest, titleAsc, titleDesc }

/// 视图模式：详细展示（原列表卡） / 紧凑网格
enum _ViewMode { detail, grid }

/// 作业列表页
class HomeworkPage extends StatefulWidget {
  const HomeworkPage({super.key});

  @override
  State<HomeworkPage> createState() => _HomeworkPageState();
}

class _HomeworkPageState extends State<HomeworkPage> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  EtsStructure? _filter;
  _SortMode _sort = _SortMode.newest;
  _ViewMode _view = _ViewMode.detail;
  bool _autoView = true;
  bool _showDone = false;
  bool _showTopBtn = false;

  // 一键批量生成缺失标题
  bool _batchTitle = false;

  Future<void> _runBatchTitle() async {
    setState(() => _batchTitle = true);
    final r = await TitleBatchService.run();
    if (r.ok > 0) Achievements.unlock('batch_title');
    if (mounted) {
      setState(() => _batchTitle = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            r.error.isNotEmpty
                ? r.error
                : '已为 ${r.ok}/${r.total} 份作业生成 AI 标题（单次请求）',
          ),
        ),
      );
    }
  }

  // 刷新中（含 Android 提权提取过程，期间按钮转圈）
  bool _refreshing = false;

  /// 统一刷新入口：Android 上先经 Root/Shizuku 提取再扫描，其余直接扫描
  Future<void> _refresh({bool silent = false}) async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    final messenger = ScaffoldMessenger.of(context);
    final (ok, msg) = await ExtractService.refresh();
    if (!mounted) return;
    setState(() => _refreshing = false);
    if (!silent) {
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  // 多选管理
  bool _selectMode = false;
  final Set<String> _selectedKeys = {};

  // 互动教程锚点
  final _kChips = GlobalKey();
  final _kSearch = GlobalKey();
  final _kList = GlobalKey();
  final _kFab = GlobalKey();

  @override
  void initState() {
    super.initState();
    TourHub.register(0, _buildTour);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ds = EtsDataService.I;
      if (ds.entries.isEmpty && !ds.scanning) ds.rescan();
      // 若设置中请求了互动教程，进入本页自动播放
      final s = SettingsService.I;
      if (s.tourRequested) {
        s.requestTour(value: false);
        WidgetsBinding.instance.addPostFrameCallback((_) => _startTour());
      }
    });
    _search.addListener(() => setState(() {}));
    _scroll.addListener(() {
      final show = _scroll.hasClients && _scroll.offset > 500;
      if (show != _showTopBtn && mounted) setState(() => _showTopBtn = show);
    });
  }

  @override
  void dispose() {
    TourHub.unregister(0);
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _groupKey(HomeworkGroup g) => '${g.uid}||${g.structure.name}';

  String _previewOf(HomeworkEntry e) {
    final c = e.content;
    if (c == null) {
      final item = e.paper?.sections.firstOrNull?.items.firstOrNull;
      final t = item?.text ?? '';
      return t.length > 40 ? '${t.substring(0, 40)}…' : t;
    }
    return switch (c.structure) {
      EtsStructure.threeQ5A =>
        c.questions.isNotEmpty
            ? 'Q1 ${c.questions.first.ask.replaceAll('</br>', ' ')}'
            : '角色扮演',
      EtsStructure.word => c.translate.isNotEmpty ? c.translate : '单词',
      EtsStructure.read =>
        c.text.replaceAll('</br>', ' ').split(' ').take(10).join(' '),
      EtsStructure.picture => () {
        // 先清洗再截断，否则前 60 字可能全是刚被删掉的 HTML 标签残留
        final t = c.text.replaceAll(RegExp(r'<[^>]+>'), ' ').trim();
        return t.length > 60 ? '${t.substring(0, 60)}…' : t;
      }(),
      EtsStructure.repeatDialogue =>
        c.sentences.isNotEmpty
            ? '${c.sentences.first.role}: ${c.sentences.first.text}'
            : '对话跟读',
      EtsStructure.unknown => '未知题型',
    };
  }

  @override
  Widget build(BuildContext context) {
    final ds = context.watch<EtsDataService>();
    final settings = context.watch<SettingsService>();
    final cs = Theme.of(context).colorScheme;
    final wide = MediaQuery.of(context).size.width >= 700;
    // Windows 恒提供"去设置目录"；Android 仅在数据目录真实存在时提示权限
    // （目录都不存在 = 用户还没下载作业，不是权限问题，别误导）
    // 注意：没有"所有文件访问"权限时，existsSync() 对其他应用的 Android/data
    // 目录不是返回 false 而是直接抛 Permission denied——在 build 里抛 = 整页灰屏
    bool rootReachable(String r) {
      try {
        return Directory(r).existsSync();
      } catch (_) {
        return false;
      }
    }

    final showRootAction =
        Platform.isWindows ||
        SettingsService.I.activeRoots.any(rootReachable);

    final completed = settings.completedDirs;
    final deleted = settings.deletedDirs;

    final allEntries = ds.entries
        .where((e) => !deleted.contains(e.dir))
        .toList();
    final allGroups = EtsDataService.computeGroups(allEntries);

    final q = _search.text.trim().toLowerCase();
    final filtered = allEntries.where((e) {
      if (_filter != null && e.structure != _filter) return false;
      final isDone = completed.contains(e.dir);
      if (_showDone != isDone) return false;
      if (q.isNotEmpty &&
          !e.title.toLowerCase().contains(q) &&
          !e.structure.label.contains(q) &&
          !(e.content?.stid ?? e.paper?.tzid ?? '').contains(q)) {
        return false;
      }
      return true;
    }).toList();
    int ts(_SortMode m, HomeworkEntry a, HomeworkEntry b) => switch (m) {
      _SortMode.newest => b.mtime.compareTo(a.mtime),
      _SortMode.oldest => a.mtime.compareTo(b.mtime),
      _SortMode.titleAsc => a.title.toLowerCase().compareTo(
        b.title.toLowerCase(),
      ),
      _SortMode.titleDesc => b.title.toLowerCase().compareTo(
        a.title.toLowerCase(),
      ),
    };
    filtered.sort((a, b) => ts(_sort, a, b));
    final groups = EtsDataService.computeGroups(filtered);

    // 默认详细展示；网格模式自动按宽度决定列数（手机 2 列 ~ 宽屏 6 列）
    final view = _autoView ? _ViewMode.detail : _view;
    final width = MediaQuery.of(context).size.width;
    final gridCols = view == _ViewMode.grid
        ? (width >= 1500
              ? 6
              : width >= 1150
              ? 5
              : width >= 860
              ? 4
              : width >= 560
              ? 3
              : 2)
        : 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: Padding(
        // 手机端底部悬浮胶囊会盖住 FAB，抬高让位
        padding: EdgeInsets.only(
          bottom: wide ? 0 : 86 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_showTopBtn)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FloatingActionButton.small(
                  heroTag: 'top',
                  tooltip: '回到顶部',
                  onPressed: () => _scroll.animateTo(
                    0,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOut,
                  ),
                  child: const Icon(Icons.arrow_upward_rounded),
                ),
              ),
            FloatingActionButton.extended(
              key: _kFab,
              heroTag: 'rescan',
              onPressed: (_refreshing || ds.scanning) ? null : _refresh,
              // 轻透玻璃小胶囊，别做成一大块实色
              elevation: 0,
              highlightElevation: 0,
              backgroundColor: cs.primary.withValues(alpha: 0.14),
              foregroundColor: cs.primary,
              shape: const StadiumBorder(),
              extendedPadding: const EdgeInsets.symmetric(horizontal: 14),
              icon: (_refreshing || ds.scanning)
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('刷新', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
      body: GlassWall(
        child: RefreshIndicator(
          onRefresh: () => _refresh(silent: true),
          child: CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (wide)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            '作业',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                      SizedBox(
                        key: _kChips,
                        height: 44,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          // 右侧留白：最后一个筛选胶囊不贴边（也是"还能往右滑"的提示）
                          padding: const EdgeInsets.only(right: 16),
                          children: [
                            _filterChip(
                              null,
                              '${_showDone ? '已完成' : '全部'} '
                              '(${allGroups.length})',
                              cs,
                            ),
                            ...EtsStructure.values
                                .where(
                                  (s) => allGroups.any((g) => g.structure == s),
                                )
                                .map(
                                  (s) => _filterChip(
                                    s,
                                    '${s.label} '
                                    '(${allGroups.where((g) => g.structure == s).length})',
                                    cs,
                                  ),
                                ),
                            FilterChip(
                              selected: _showDone,
                              label: const Text('已完成区'),
                              avatar: const Icon(
                                Icons.check_rounded,
                                size: 15,
                              ),
                              onSelected: (v) => setState(() {
                                _showDone = v;
                                _selectMode = false;
                                _selectedKeys.clear();
                              }),
                            ),
                            // 一键批量生成缺失标题（单次请求打包全部）
                            ActionChip(
                              avatar: _batchTitle
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.auto_awesome, size: 15),
                              label: Text(
                                _batchTitle ? '生成中…' : '生成缺失标题',
                                style: const TextStyle(fontSize: 12),
                              ),
                              onPressed: _batchTitle ? null : _runBatchTitle,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      // 窄屏换行：搜索框独占一行，排序/视图/管理退到第二行
                      LayoutBuilder(
                        builder: (context, box) {
                          final narrow = box.maxWidth < 560;
                          return Wrap(
                            key: _kSearch,
                            spacing: 6,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              SizedBox(
                                width: (narrow
                                        ? box.maxWidth
                                        : box.maxWidth - 236)
                                    .clamp(180.0, box.maxWidth),
                                child: TextField(
                                  controller: _search,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: '搜索标题 / 题号…',
                                    prefixIcon: const Icon(
                                      Icons.search,
                                      size: 20,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ),
                              PopupMenuButton<_SortMode>(
                            tooltip: '排序方式',
                            onSelected: (v) => setState(() => _sort = v),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: _SortMode.newest,
                                child: Text('时间 · 最新优先'),
                              ),
                              PopupMenuItem(
                                value: _SortMode.oldest,
                                child: Text('时间 · 最早优先'),
                              ),
                              PopupMenuItem(
                                value: _SortMode.titleAsc,
                                child: Text('标题 · A → Z'),
                              ),
                              PopupMenuItem(
                                value: _SortMode.titleDesc,
                                child: Text('标题 · Z → A'),
                              ),
                            ],
                            child: Chip(
                              avatar: Icon(
                                Icons.sort_rounded,
                                size: 16,
                                color: cs.primary,
                              ),
                              label: Text(switch (_sort) {
                                _SortMode.newest => '最新',
                                _SortMode.oldest => '最早',
                                _SortMode.titleAsc => 'A-Z',
                                _SortMode.titleDesc => 'Z-A',
                              }, style: Theme.of(context).textTheme.labelSmall),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                              PopupMenuButton<int>(
                            tooltip: '展示方式',
                            onSelected: (v) => setState(() {
                              if (v == -1) {
                                _autoView = true;
                              } else {
                                _autoView = false;
                                _view = v == 1
                                    ? _ViewMode.grid
                                    : _ViewMode.detail;
                              }
                            }),
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: -1,
                                child: Row(
                                  children: [
                                    if (_autoView)
                                      const Icon(Icons.check, size: 16),
                                    if (!_autoView) const SizedBox(width: 16),
                                    const Text('自动（详细展示）'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 0,
                                child: Text('详细展示'),
                              ),
                              const PopupMenuItem(
                                value: 1,
                                child: Text('紧凑网格（小卡片）'),
                              ),
                            ],
                            child: Chip(
                              avatar: Icon(
                                _autoView
                                    ? Icons.auto_mode_rounded
                                    : view == _ViewMode.detail
                                    ? Icons.view_list_rounded
                                    : Icons.grid_view_rounded,
                                size: 16,
                                color: cs.primary,
                              ),
                              label: Text(
                                _autoView
                                    ? '自动'
                                    : view == _ViewMode.detail
                                    ? '详细'
                                    : '紧凑',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                              IconButton(
                                tooltip: '管理作业',
                                icon: const Icon(
                                  Icons.checklist_rounded,
                                  size: 20,
                                ),
                                onPressed: () => setState(() {
                                  _selectMode = true;
                                  _selectedKeys.clear();
                                }),
                              ),
                            ],
                          );
                        },
                      ),
                      if (deleted.isNotEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () {
                              settings.restoreDeleted();
                              setState(() {});
                            },
                            icon: const Icon(Icons.restore_rounded, size: 16),
                            label: Text('恢复已删除的 ${deleted.length} 项'),
                          ),
                        ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
              if (_selectMode)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    // 窄屏放不下「计数 + 4 个操作」，用 Wrap 换行而不是溢出
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '已选 ${_selectedKeys.length} 个文件夹',
                          style: const TextStyle(fontSize: 12),
                        ),
                        TextButton(
                          onPressed: () => _selectAll(groups),
                          child: const Text('全选'),
                        ),
                        TextButton.icon(
                          onPressed: _selectedKeys.isEmpty
                              ? null
                              : () => _bulkDelete(groups),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 16,
                          ),
                          label: const Text('永久删除'),
                        ),
                        TextButton.icon(
                          onPressed: _selectedKeys.isEmpty
                              ? null
                              : () => _bulkComplete(
                                  groups,
                                  _showDone ? false : true,
                                ),
                          icon: const Icon(
                            Icons.check_circle_outline_rounded,
                            size: 16,
                          ),
                          label: Text(_showDone ? '恢复' : '完成'),
                        ),
                        IconButton(
                          tooltip: '退出多选',
                          onPressed: _exitSelect,
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                      ],
                    ),
                  ),
                ),
              if (ds.scanning && ds.entries.isEmpty)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(
                    onPickRoot: showRootAction ? _pickRoot : null,
                    onWalkthrough: Platform.isAndroid ? _openWalkthrough : null,
                  ),
                )
              else if (gridCols == 0)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
                  sliver: SliverList.separated(
                    itemCount: groups.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _buildItem(
                      context,
                      groups[i],
                      key: i == 0 ? _kList : null,
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: gridCols,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.35,
                    ),
                    itemCount: groups.length,
                    itemBuilder: (context, i) => _GroupTile(
                      g: groups[i],
                      onTap: () => _selectMode
                          ? _toggleSelect(groups[i])
                          : _open(groups[i]),
                      onLongPress: () => _enterSelect(groups[i]),
                      selecting: _selectMode,
                      selected: _selectedKeys.contains(_groupKey(groups[i])),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, HomeworkGroup g, {Key? key}) {
    return _GroupCard(
      // 教程锚点只挂第一张卡（同一 GlobalKey 不能给多张卡）
      key: key,
      group: g,
      onTap: () => _open(g),
      onLongPress: () => _enterSelect(g),
      selecting: _selectMode,
      selected: _selectedKeys.contains(_groupKey(g)),
      preview: _previewOf(g.entries.first),
      onDoneToggle: () => _toggleDone(g),
    );
  }

  void _open(HomeworkGroup g) {
    if (_selectMode) {
      _toggleSelect(g);
      return;
    }
    if (g.entries.length == 1) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ContentDetailPage(entry: g.entries.first),
        ),
      );
    } else {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => GroupPage(group: g)));
    }
  }

  // ---- 多选管理 ----
  void _enterSelect(HomeworkGroup g) {
    setState(() {
      _selectMode = true;
      _toggleSelect(g);
    });
  }

  void _toggleSelect(HomeworkGroup g) {
    setState(() {
      final k = _groupKey(g);
      if (_selectedKeys.contains(k)) {
        _selectedKeys.remove(k);
      } else {
        _selectedKeys.add(k);
      }
    });
  }

  void _exitSelect() => setState(() {
    _selectMode = false;
    _selectedKeys.clear();
  });

  List<HomeworkGroup> _selectedGroups(List<HomeworkGroup> visible) =>
      visible.where((g) => _selectedKeys.contains(_groupKey(g))).toList();

  void _selectAll(List<HomeworkGroup> visible) {
    setState(() {
      if (_selectedKeys.length >= visible.length) {
        _selectedKeys.clear();
      } else {
        _selectedKeys
          ..clear()
          ..addAll(visible.map(_groupKey));
      }
    });
  }

  void _bulkComplete(List<HomeworkGroup> visible, bool done) {
    // 收纳计数
    final groups = _selectedGroups(visible);
    final keys = groups.expand((g) => g.entries.map((e) => e.dir)).toList();
    SettingsService.I.setCompleted(keys, done);
    Achievements.bump('collector');
    _exitSelect();
    setState(() {});
    _toast(done ? '已标记完成，收纳到「已完成区」' : '已恢复为未完成');
  }

  /// 永久删除：直接删除磁盘上的作业文件夹（不可恢复，二次确认）
  Future<void> _bulkDelete(List<HomeworkGroup> visible) async {
    final groups = _selectedGroups(visible);
    if (groups.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('永久删除 ${groups.length} 个作业文件夹？'),
        content: Text(
          '将删除磁盘上这 ${groups.length} 个文件夹及其中的全部作业数据，'
          '此操作不可恢复。\n如果只是暂时不看，建议用「完成」收纳起来。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    Achievements.unlock('cleaner');
    var failed = 0;
    for (final g in groups) {
      for (final e in g.entries) {
        try {
          final d = Directory(e.dir);
          if (await d.exists()) await d.delete(recursive: true);
        } catch (_) {
          failed++;
        }
      }
    }
    final keys = groups.expand((g) => g.entries.map((e) => e.dir)).toList();
    SettingsService.I.forgetDirs(keys);
    _exitSelect();
    await EtsDataService.I.rescan();
    if (mounted) {
      _toast(
        failed == 0
            ? '已永久删除 ${groups.length} 个文件夹'
            : '已删除 ${groups.length - failed} 个，$failed 个失败（可能正被占用）',
      );
    }
  }

  void _toggleDone(HomeworkGroup g) {
    final s = SettingsService.I;
    final done = s.completedDirs.contains(g.entries.first.dir);
    final keys = g.entries.map((e) => e.dir).toList();
    s.setCompleted(keys, !done);
    setState(() {});
    _toast(done ? '已恢复显示' : '已标记完成并收纳到「已完成区」');
  }

  void _startTour() {
    if (!mounted) return;
    InteractiveTour.show(context, _buildTour());
  }

  /// 作业页引导：每一步都锚到真实控件（此前全部传 null，蒙层不挖洞）
  List<TourStep> _buildTour() => [
    TourStep(_kChips, '按类型筛选', '这里按题型筛选：全部 / 模仿朗读 / 角色扮演… 括号里是文件夹数量。'),
    TourStep(
      _kSearch,
      '搜索 · 排序 · 视图',
      '搜索标题或题号；右侧可切排序（时间正倒序 / 标题）与视图（详细列表 / 紧凑网格）。',
    ),
    TourStep(_kList, '作业卡片', '点击看答案与精听；长按进入多选，可全选、标记完成（收纳到「已完成区」）、永久删除。'),
    TourStep(
      _kFab,
      '刷新数据',
      '点「刷新」重新读取 E听说 作业数据；手机上会先经 Root / Shizuku 自动提取再加载。',
    ),
  ];

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickRoot() async {
    if (Platform.isAndroid) {
      final ok = await SettingsService.requestAndroidStorage();
      if (!mounted) return;
      if (!ok) {
        _toast('需要"所有文件访问"权限才能读取 E听说 作业数据');
      }
      _refresh(silent: true);
    } else {
      _toast('请在"设置"页添加 ETS 数据目录');
    }
  }

  /// 安卓：空态点「一步步教你提取」打开分步引导
  Future<void> _openWalkthrough() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetCtx).height * 0.8,
        ),
        child: ExtractWalkthrough(
          onExtract: (msg) async {
            if (!mounted) return;
            Navigator.of(sheetCtx).pop();
            _toast(msg);
            await _refresh(silent: true);
          },
        ),
      ),
    );
  }

  Widget _filterChip(EtsStructure? s, String label, ColorScheme cs) {
    final selected = _filter == s;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: selected,
        label: Text(label),
        onSelected: (_) => setState(() => _filter = s),
      ),
    );
  }
}

/// 列表样式分组卡片
class _GroupCard extends StatelessWidget {
  final HomeworkGroup group;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDoneToggle;
  final bool selecting;
  final bool selected;
  final String preview;
  const _GroupCard({
    super.key,
    required this.group,
    required this.onTap,
    required this.onLongPress,
    required this.onDoneToggle,
    required this.selecting,
    required this.selected,
    required this.preview,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final done = context.watch<SettingsService>().completedDirs.contains(
      group.entries.first.dir,
    );
    final dateStr = DateFormat('MM-dd HH:mm:ss')
        .format(group.entries.first.mtime);
    final words = group.entries.length;

    return Container(
      decoration: BoxDecoration(
        color: selected
            ? cs.primary.withValues(alpha: 0.12)
            : cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected
              ? cs.primary
              : done
              ? Colors.green.withValues(alpha: 0.4)
              : cs.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              if (selecting)
                Checkbox(value: selected, onChanged: (_) => onTap())
              else
                _TypeIcon(structure: group.structure, done: done),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _chinaTitleOf(group.entries.first) ==
                                    group.entries.first.title
                                ? group.displayName
                                : (group.entries.length == 1
                                      ? _chinaTitleOf(group.entries.first)
                                      : group.displayName),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 6),
                        TitleSourceBadge(group.entries.first.titleSource),
                        if (done)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.check_rounded,
                              size: 15,
                              color: Colors.green.shade600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: cs.outline),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      group.structure == EtsStructure.word
                          ? '$words 个单词 · $dateStr'
                          : '$words 份内容 · $dateStr',
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: cs.outline.withValues(alpha: 0.8)),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: done ? '恢复未完成' : '标记完成并收纳',
                onPressed: onDoneToggle,
                icon: Icon(
                  done
                      ? Icons.undo_rounded
                      : Icons.check_circle_outline_rounded,
                  size: 20,
                  color: done ? Colors.green : null,
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.outline),
            ],
          ),
        ),
      ),
    );
  }
}

/// 网格紧凑小卡片：小图标 + 中文标题一行 + 类别/数量微标
class _GroupTile extends StatelessWidget {
  final HomeworkGroup g;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selecting;
  final bool selected;
  const _GroupTile({
    required this.g,
    required this.onTap,
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final done = context.watch<SettingsService>().completedDirs.contains(
      g.entries.first.dir,
    );
    // 中文标题优先：AI/模板标题直接用；否则 类型｜摘要（服务层已生成中文前缀）
    final title = g.entries.first.title;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: done
              ? Colors.green.withValues(alpha: 0.4)
              : cs.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              _TypeIcon(structure: g.structure, done: done, small: true),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            g.structure.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: cs.primary),
                          ),
                        ),
                        if (g.entries.length > 1) ...[
                          const SizedBox(width: 4),
                          Text(
                            '${g.entries.length} 份',
                            style: TextStyle(fontSize: 12, color: cs.outline),
                          ),
                        ],
                        if (done) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.check_rounded,
                            size: 12,
                            color: Colors.green.shade600,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 类型图标
class _TypeIcon extends StatelessWidget {
  final EtsStructure structure;
  final bool done;
  final bool small;
  const _TypeIcon({
    required this.structure,
    required this.done,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = small ? 30.0 : 44.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: done
            ? Colors.green.withValues(alpha: 0.12)
            : cs.primaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(small ? 9 : 12),
      ),
      child: Icon(
        done
            ? Icons.check_rounded
            : switch (structure) {
                EtsStructure.word => Icons.abc_rounded,
                EtsStructure.read => Icons.article_rounded,
                EtsStructure.threeQ5A => Icons.question_answer_rounded,
                EtsStructure.picture => Icons.image_rounded,
                EtsStructure.repeatDialogue => Icons.record_voice_over_rounded,
                EtsStructure.unknown => Icons.help_outline_rounded,
              },
        color: done ? Colors.green : cs.primary,
        size: small ? 17 : 22,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback? onPickRoot;
  final VoidCallback? onWalkthrough;
  const _EmptyState({required this.onPickRoot, this.onWalkthrough});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 图标：玻璃圆底 + 主色，缩到 44（原 64 灰图标在手机上过于抢眼）
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.primary.withValues(alpha: 0.10),
                border: Border.all(color: cs.primary.withValues(alpha: 0.22)),
              ),
              child: Icon(
                Icons.folder_open_rounded,
                size: 28,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '未找到 E听说 作业数据',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              Platform.isWindows
                  ? '默认目录：${SettingsService.platformDefaultRoot}\n'
                        '先用 E听说 客户端下载作业，或到"设置"里添加数据目录。'
                  : (onPickRoot == null
                        ? '先用 E听说 客户端下载作业，下载后这里会自动出现。'
                        : '需要"所有文件访问"权限，并确保已用 E听说 APP 下载过作业。'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: cs.outline),
            ),
            if (onPickRoot != null) ...[
              const SizedBox(height: 14),
              FilledButton.tonalIcon(
                onPressed: onPickRoot,
                icon: const Icon(Icons.folder_open_rounded),
                label: Text(Platform.isWindows ? '去设置目录' : '申请存储权限'),
              ),
            ],
            if (onWalkthrough != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onWalkthrough,
                icon: const Icon(Icons.school_rounded, size: 18),
                label: const Text('一步步教你提取数据'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 中文展示标题：标题无中文时补「类型｜」前缀
String _chinaTitleOf(HomeworkEntry e) {
  final t = e.title.trim();
  if (RegExp(r'[一-鿿]').hasMatch(t)) return t;
  return '${e.structure.label}｜$t';
}
