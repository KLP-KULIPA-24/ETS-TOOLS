import io

p = 'lib/pages/homework_page.dart'
s = io.open(p, encoding='utf-8').read()

# 1) 视图模式：详细展示（默认） / 紧凑网格
s = s.replace('''/// 视图模式：列表 / 两列 / 三列
enum _ViewMode { list, grid2, grid3 }''',
'''/// 视图模式：详细展示（原列表卡） / 紧凑网格
enum _ViewMode { detail, grid }''')

s = s.replace('''  _ViewMode _view = _ViewMode.list;''',
              '''  _ViewMode _view = _ViewMode.detail;''')

# 2) build 中视图计算与渲染分支
s = s.replace('''    final view = _autoView ? (wide ? _ViewMode.grid3 : _ViewMode.list) : _view;
    final gridCols = view == _ViewMode.grid2
        ? 2
        : view == _ViewMode.grid3
            ? 3
            : 0;''',
'''    // 默认详细展示；网格模式自动按宽度决定列数（3~6 列，紧凑小卡片）
    final view = _autoView ? _ViewMode.detail : _view;
    final width = MediaQuery.of(context).size.width;
    final gridCols = view == _ViewMode.grid
        ? (width >= 1500
            ? 6
            : width >= 1150
                ? 5
                : width >= 860
                    ? 4
                    : 3)
        : 0;''')

# 3) 视图切换菜单
s = s.replace('''                            itemBuilder: (_) => [
                              PopupMenuItem(
                                  value: -1,
                                  child: Row(children: [
                                    if (_autoView)
                                      const Icon(Icons.check, size: 16),
                                    if (!_autoView) const SizedBox(width: 16),
                                    const Text('自动'),
                                  ])),
                              const PopupMenuItem(value: 0, child: Text('列表')),
                              const PopupMenuItem(
                                  value: 2, child: Text('两列网格')),
                              const PopupMenuItem(
                                  value: 3, child: Text('三列网格')),
                            ],''',
'''                            itemBuilder: (_) => [
                              PopupMenuItem(
                                  value: -1,
                                  child: Row(children: [
                                    if (_autoView)
                                      const Icon(Icons.check, size: 16),
                                    if (!_autoView) const SizedBox(width: 16),
                                    const Text('自动（详细展示）'),
                                  ])),
                              const PopupMenuItem(
                                  value: 0, child: Text('详细展示')),
                              const PopupMenuItem(
                                  value: 1, child: Text('紧凑网格（小卡片）')),
                            ],''')

s = s.replace('''                            onSelected: (v) => setState(() {
                              if (v == -1) {
                                _autoView = true;
                              } else {
                                _autoView = false;
                                _view = v == 2
                                    ? _ViewMode.grid2
                                    : _ViewMode.grid3;
                              }
                            }),''',
'''                            onSelected: (v) => setState(() {
                              if (v == -1) {
                                _autoView = true;
                              } else {
                                _autoView = false;
                                _view = v == 1
                                    ? _ViewMode.grid
                                    : _ViewMode.detail;
                              }
                            }),''')

s = s.replace('''                              avatar: Icon(
                                  _autoView
                                      ? Icons.auto_mode_rounded
                                      : view == _ViewMode.list
                                          ? Icons.view_list_rounded
                                          : Icons.grid_view_rounded,
                                  size: 16,
                                  color: cs.primary),
                              label: Text(
                                _autoView
                                    ? '自动'
                                    : view == _ViewMode.list
                                        ? '列表'
                                        : '$gridCols列',''',
'''                              avatar: Icon(
                                  _autoView
                                      ? Icons.auto_mode_rounded
                                      : view == _ViewMode.detail
                                          ? Icons.view_list_rounded
                                          : Icons.grid_view_rounded,
                                  size: 16,
                                  color: cs.primary),
                              label: Text(
                                _autoView
                                    ? '自动'
                                    : view == _ViewMode.detail
                                        ? '详细'
                                        : '紧凑',''')

# 4) 网格 delegate：紧凑比例（宽扁小卡）
s = s.replace('''                    gridDelegate:
                        SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: gridCols,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.92,
                    ),''',
'''                    gridDelegate:
                        SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: gridCols,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.35,
                    ),''')

io.open(p, 'w', encoding='utf-8').write(s)
print('view patch ok')
