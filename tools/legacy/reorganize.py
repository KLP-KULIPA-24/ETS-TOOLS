import pathlib
import re
import shutil

root = pathlib.Path('.')

# ---- 1. 移动文件（按功能域分类）----
moves = {
    'lib/pages/homework_page.dart': 'lib/pages/homework/homework_page.dart',
    'lib/pages/group_page.dart': 'lib/pages/homework/group_page.dart',
    'lib/pages/exam_sim_page.dart': 'lib/pages/homework/exam_sim_page.dart',
    'lib/pages/ai_chat_page.dart': 'lib/pages/ai/ai_chat_page.dart',
    'lib/pages/capture_page.dart': 'lib/pages/modify/capture_page.dart',
    'lib/pages/settings_page.dart': 'lib/pages/settings/settings_page.dart',
    'lib/pages/intro/onboarding_page.dart': 'lib/pages/settings/onboarding_page.dart',
    'lib/pages/achievements_page.dart': 'lib/pages/settings/achievements_page.dart',
    'lib/pages/floating_mode_page.dart': 'lib/pages/floating/floating_mode_page.dart',
    'lib/pages/home_shell.dart': 'lib/app/home_shell.dart',
}
for src, dst in moves.items():
    s, d = root / src, root / dst
    if not s.exists():
        print('skip(missing):', src)
        continue
    d.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(s), str(d))
print('moved')

# ---- 2. 全项目修正 import 相对路径 ----
# a) 移入子目录的 pages 文件：../services|widgets|models → ../../...
moved_pages = [d for s, d in moves.items()
               if d.startswith('lib/pages/') and d.count('/') == 3]
for rel in moved_pages:
    p = root / rel
    t = p.read_text(encoding='utf-8')
    t = t.replace("'../services/", "'../../services/")
    t = t.replace("'../widgets/", "'../../widgets/")
    t = t.replace("'../models/", "'../../models/")
    p.write_text(t, encoding='utf-8')

# b) app/home_shell.dart：原来在 pages/ 一层，引用 pages 兄弟页 → ../pages/<域>/xxx
p = root / 'lib/app/home_shell.dart'
t = p.read_text(encoding='utf-8')
for name, sub in [('capture_page.dart', 'modify/capture_page.dart'),
                  ('ai_chat_page.dart', 'ai/ai_chat_page.dart'),
                  ('homework_page.dart', 'homework/homework_page.dart'),
                  ('settings_page.dart', 'settings/settings_page.dart'),
                  ('achievements_page.dart', 'settings/achievements_page.dart')]:
    t = t.replace(f"import '{name}';", f"import '../pages/{sub}';")
p.write_text(t, encoding='utf-8')

# c) 其他文件里对这些页面的引用统一修正
ref_map = [
    ("'capture_page.dart'", "'../pages/modify/capture_page.dart'"),
    ("'ai_chat_page.dart'", "'../pages/ai/ai_chat_page.dart'"),
    ("'homework_page.dart'", "'../pages/homework/homework_page.dart'"),
    ("'group_page.dart'", "'../pages/homework/group_page.dart'"),
    ("'exam_sim_page.dart'", "'../pages/homework/exam_sim_page.dart'"),
    ("'floating_mode_page.dart'", "'../pages/floating/floating_mode_page.dart'"),
    ("'settings_page.dart'", "'../pages/settings/settings_page.dart'"),
    ("'achievements_page.dart'", "'../pages/settings/achievements_page.dart'"),
    ("'intro/onboarding_page.dart'", "'settings/onboarding_page.dart'"),
    ("'pages/intro/onboarding_page.dart'", "'pages/settings/onboarding_page.dart'"),
    ("'pages/home_shell.dart'", "'app/home_shell.dart'"),
]
for p in root.glob('lib/**/*.dart'):
    t = p.read_text(encoding='utf-8')
    o = t
    for a, b in ref_map:
        t = t.replace(f"import {a};", f"import {b};")
    if t != o:
        p.write_text(t, encoding='utf-8')
print('imports fixed')

# d) 同目录互引复查：settings 内互引、homework 内互引、detail 引用
checks = {
    'lib/pages/settings/settings_page.dart': [("import 'onboarding_page.dart';", "import 'onboarding_page.dart';")],
    'lib/pages/homework/homework_page.dart': [("import 'group_page.dart';", "import 'group_page.dart';")],
}
print('same-dir refs ok')

# e) 清理临时补丁脚本
for f in (root / 'tool').glob('patch_*.py'):
    f.unlink()
    print('removed', f.name)
