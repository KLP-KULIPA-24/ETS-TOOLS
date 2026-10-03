import 'package:flutter/material.dart';

import 'interactive_tour.dart';

/// 一个教程章节（对应一个导航页）
class TourChapter {
  final int pageIndex;
  final String title;
  final String desc;
  final IconData icon;

  const TourChapter(this.pageIndex, this.title, this.desc, this.icon);
}

/// 教程中枢：各页面在 initState 注册自己的步骤（含 GlobalKey 闭包），
/// 顶栏「?」统一从这里唤起。页面自己持有 GlobalKey，所以步骤必须在页面内构建。
class TourHub {
  TourHub._();

  static final Map<int, List<TourStep> Function()> _builders = {};

  /// 全部章节（顺序 = 顶栏帮助面板与设置页的展示顺序）
  static const chapters = <TourChapter>[
    TourChapter(0, '作业列表', '筛选、搜索排序、视图切换、多选管理与刷新提取', Icons.assignment_rounded),
    TourChapter(1, 'AI 对话', '多会话、打断续传、思考面板、token 统计', Icons.forum_rounded),
    TourChapter(2, '修改', '抓包拦截配置与成绩 / 完成时间规则', Icons.tune_rounded),
    TourChapter(3, '成就', '解锁记录与统计', Icons.emoji_events_rounded),
  ];

  static void register(int pageIndex, List<TourStep> Function() build) {
    _builders[pageIndex] = build;
  }

  static void unregister(int pageIndex) {
    _builders.remove(pageIndex);
  }

  static bool has(int pageIndex) => _builders.containsKey(pageIndex);

  /// 请求切到某页并播放引导。由 HomeShell 监听（它才知道怎么切页），
  /// 这样设置页等非导航容器也能唤起其它页的教程。
  static final request = ValueNotifier<int?>(null);

  /// 播放指定页面的引导；该页未注册则什么也不做
  static void show(BuildContext context, int pageIndex) {
    final build = _builders[pageIndex];
    if (build == null) return;
    final steps = build();
    if (steps.isEmpty) return;
    InteractiveTour.show(context, steps);
  }

  /// 顶栏「?」/ 设置页「功能引导」：先列章节，选中后跳到对应页再播引导。
  /// 无论从哪个容器唤起，都走 [request] 让 HomeShell 统一切页。
  static Future<void> showHelpSheet(BuildContext context) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                '使用教程',
                style: Theme.of(sheetCtx).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '选一个功能看图文引导',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(sheetCtx).colorScheme.outline,
                ),
              ),
            ),
            for (final c in chapters)
              ListTile(
                leading: Icon(
                  c.icon,
                  color: Theme.of(sheetCtx).colorScheme.primary,
                ),
                title: Text(c.title, style: const TextStyle(fontSize: 14)),
                subtitle: Text(c.desc, style: const TextStyle(fontSize: 12)),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: Theme.of(sheetCtx).colorScheme.outline,
                ),
                // 点当前页直接播；点别的页先切过去
                onTap: () => Navigator.pop(sheetCtx, c.pageIndex),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null) return;
    // 交给 HomeShell 切页并延后播放（它才有切页能力）
    request.value = picked;
  }
}
