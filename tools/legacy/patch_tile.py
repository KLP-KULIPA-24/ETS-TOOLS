import io

p = 'lib/pages/homework_page.dart'
s = io.open(p, encoding='utf-8').read()

old = '''/// 网格紧凑卡片：图标在上、标题居中、类别角标
class _GroupTile extends StatelessWidget {
  final HomeworkGroup g;
  final VoidCallback onTap;
  const _GroupTile({required this.g, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final done = context
        .watch<SettingsService>()
        .completedDirs
        .contains(g.entries.first.dir);
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: done
                ? Colors.green.withValues(alpha: 0.4)
                : cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _TypeIcon(structure: g.structure, done: done, big: true),
              const SizedBox(height: 8),
              Text(g.entries.first.title,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TypeBadge(g.structure),
              if (g.entries.length > 1) ...[
                const SizedBox(height: 6),
                Text('${g.entries.length} 份',
                    style: TextStyle(fontSize: 11, color: cs.outline)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}'''

new = '''/// 网格紧凑小卡片：小图标 + 中文标题一行 + 类别/数量微标
class _GroupTile extends StatelessWidget {
  final HomeworkGroup g;
  final VoidCallback onTap;
  const _GroupTile({required this.g, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final done = context
        .watch<SettingsService>()
        .completedDirs
        .contains(g.entries.first.dir);
    // 中文标题优先：AI/模板标题直接用；否则 类型｜摘要（服务层已生成中文前缀）
    final title = g.entries.first.title;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: done
                ? Colors.green.withValues(alpha: 0.4)
                : cs.outlineVariant.withValues(alpha: 0.5)),
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
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(g.structure.label,
                            style: TextStyle(
                                fontSize: 10.5, color: cs.primary)),
                        if (g.entries.length > 1) ...[
                          const SizedBox(width: 6),
                          Text('${g.entries.length} 份',
                              style: TextStyle(
                                  fontSize: 10.5, color: cs.outline)),
                        ],
                        if (done) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.check_circle_rounded,
                              size: 12, color: Colors.green.shade600),
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
}'''
assert old in s, 'tile not found'
s = s.replace(old, new, 1)

# _TypeIcon 支持 small
s = s.replace('''class _TypeIcon extends StatelessWidget {
  final EtsStructure structure;
  final bool done;
  final bool big;
  const _TypeIcon(
      {required this.structure, required this.done, this.big = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = big ? 46.0 : 44.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: done
            ? Colors.green.withValues(alpha: 0.12)
            : cs.primaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(big ? 14 : 12),
      ),''','''class _TypeIcon extends StatelessWidget {
  final EtsStructure structure;
  final bool done;
  final bool big;
  final bool small;
  const _TypeIcon(
      {required this.structure,
      required this.done,
      this.big = false,
      this.small = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = small ? 30.0 : (big ? 46.0 : 44.0);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: done
            ? Colors.green.withValues(alpha: 0.12)
            : cs.primaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(small ? 9 : (big ? 14 : 12)),
      ),''')
s = s.replace('''        color: done ? Colors.green : cs.primary,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {''','''        color: done ? Colors.green : cs.primary,
        size: small ? 17 : null,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {''')

io.open(p, 'w', encoding='utf-8').write(s)
print('tile patch ok')
