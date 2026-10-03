import io, glob

def patch(path, pairs, must=True):
    s = io.open(path, encoding='utf-8').read()
    for old, new in pairs:
        if old not in s:
            if must:
                raise AssertionError(f'{path}: missing {old[:70]!r}')
            continue
        s = s.replace(old, new, 1)
    io.open(path, 'w', encoding='utf-8').write(s)
    print('ok', path)

# ============ 1) SectionCard → 实底 AppCard（内容层禁玻璃） ============
patch('lib/widgets/common.dart', [
    ("import 'glass.dart';", "import 'style.dart';"),
    ('''    final cs = Theme.of(context).colorScheme;
    return GlassContainer(
      radius: 18,
      margin: const EdgeInsets.only(bottom: 14),''',
     '''    final cs = Theme.of(context).colorScheme;
    return AppCard(
      radius: 16,
      margin: const EdgeInsets.only(bottom: 14),'''),
])

# ============ 2) 内容页 GlassContainer → AppCard ============
for f in ['lib/pages/settings_page.dart', 'lib/pages/capture_page.dart',
          'lib/pages/ai_chat_page.dart']:
    s = io.open(f, encoding='utf-8').read()
    n = s.count('GlassContainer(')
    s = s.replace('GlassContainer(', 'AppCard(')
    # AppCard 没有 radius=20 默认差异，无需处理；补 style.dart 导入
    if "import '../widgets/style.dart';" not in s:
        s = s.replace("import '../widgets/glass.dart';",
                      "import '../widgets/glass.dart';\nimport '../widgets/style.dart';")
    io.open(f, 'w', encoding='utf-8').write(s)
    print(f'content cards -> AppCard ({n} 处)', f)

# ============ 3) GlassAppBar 工具栏玻璃化 ============
patch('lib/pages/ai_chat_page.dart', [
    ('''  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppBar(
      backgroundColor: Colors.transparent,''',
     '''  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      radius: BorderRadius.zero,
      child: AppBar(
      backgroundColor: Colors.transparent,'''),
])

# 收尾括号：GlassAppBar 的 build 需要多一层闭合
s = io.open('lib/pages/ai_chat_page.dart', encoding='utf-8').read()
old_close = '''      actions: actions,
    );
  }
}'''
new_close = '''        actions: actions,
      ),
    );
  }
}'''
assert old_close in s
s = s.replace(old_close, new_close, 1)
io.open('lib/pages/ai_chat_page.dart', 'w', encoding='utf-8').write(s)
print('glass appbar ok')

# ============ 4) 悬浮窗面板 → LiquidGlass（控制层） + 按压反馈 ============
patch('lib/pages/floating_mode_page.dart', [
    ("import '../widgets/ai_panel.dart';",
     "import '../style/style.dart';") if False else ("import '../services/settings_service.dart';",
     "import '../services/settings_service.dart';\nimport '../widgets/style.dart';"),
    ('''      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Container(
          decoration: BoxDecoration(
            color: dark
                ? const Color(0xFF0F141D).withValues(alpha: 0.95)
                : const Color(0xFFFBFCFF).withValues(alpha: 0.97),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: cs.primaryContainer),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 30,
                  offset: const Offset(0, 10)),
            ],
          ),
          child: Column(''',
     '''      child: LiquidGlass(
        radius: BorderRadius.circular(26),
        child: Column('''),
])

# 收缩图标加按压反馈
patch('lib/pages/floating_mode_page.dart', [
    ('''      child: GestureDetector(
        onTap: () => setState(() {
          expanded = true;
          _applyWindow();
        }),
        onPanStart: (_) => windowManager.startDragging(),
        onPanUpdate: (_) {},
        onPanEnd: (_) {},
        child: MouseRegion(''',
     '''      child: PressableScale(
        onTap: () => setState(() {
          expanded = true;
          _applyWindow();
        }),
        onLongPress: null,
        child: GestureDetector(
        onPanStart: (_) => windowManager.startDragging(),
        child: MouseRegion('''),
])
# 闭合修正：MouseRegion/GestureDetector 需要多一层
s = io.open('lib/pages/floating_mode_page.dart', encoding='utf-8').read()
old = '''              borderRadius: BorderRadius.circular(24),
              child: Image.asset('assets/icon.png', fit: BoxFit.cover),
            ),
          ),
        ),
      ),
    );
  }'''
new = '''              borderRadius: BorderRadius.circular(24),
              child: Image.asset('assets/icon.png', fit: BoxFit.cover),
            ),
          ),
        ),
      ),
      ),
    );
  }'''
assert old in s
s = s.replace(old, new, 1)
io.open('lib/pages/floating_mode_page.dart', 'w', encoding='utf-8').write(s)
print('win floating press ok')

# ============ 5) 安卓悬浮窗面板玻璃化 ============
patch('lib/overlay_main.dart', [
    ("import 'services/settings_service.dart';",
     "import 'services/settings_service.dart';\nimport 'widgets/style.dart';"),
    ('''        child: Container(
          key: const ValueKey('panel'),
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.primaryContainer),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(''',
     '''        child: LiquidGlass(
          radius: BorderRadius.circular(24),
          padding: const EdgeInsets.all(14),
          child: Column('''),
])
s = io.open('lib/overlay_main.dart', encoding='utf-8').read()
old = '''                  : const Icon(Icons.send_rounded, size: 20),
            ),
          ],
        ),
      ),
    );
  }'''
new = '''                  : const Icon(Icons.send_rounded, size: 20),
            ),
          ],
        ),
      ),
      ),
    );
  }'''
assert old in s
s = s.replace(old, new, 1)
io.open('lib/overlay_main.dart', 'w', encoding='utf-8').write(s)
print('android overlay glass ok')

# ============ 6) 底部导航：Q 弹 + 按压反馈（style 版玻璃） ============
patch('lib/pages/home_shell.dart', [
    ("import '../widgets/glass.dart';",
     "import '../widgets/glass.dart';\nimport '../widgets/style.dart';"),
    ('''                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      index == i ? items[i].$2 : items[i].$1,
                      size: 21,
                      color:
                          index == i ? cs.primary : cs.onSurfaceVariant,
                    ),
                    const SizedBox(height: 2),
                    Text(items[i].$3,
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: index == i
                                ? FontWeight.bold
                                : FontWeight.w600,
                            color: index == i
                                ? cs.primary
                                : cs.onSurfaceVariant)),
                  ],
                ),''',
     '''                child: Qbounce(
                  trigger: index == i ? 1 : 0,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        index == i ? items[i].$2 : items[i].$1,
                        size: 21,
                        color:
                            index == i ? cs.primary : cs.onSurfaceVariant,
                      ),
                      const SizedBox(height: 2),
                      Text(items[i].$3,
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: index == i
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: index == i
                                  ? cs.primary
                                  : cs.onSurfaceVariant)),
                    ],
                  ),
                ),'''),
])

print('all style patches done')
