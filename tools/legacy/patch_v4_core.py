import io, re, glob

def patch(path, pairs, must=True):
    s = io.open(path, encoding='utf-8').read()
    for old, new in pairs:
        if old not in s:
            if must:
                raise AssertionError(f'{path}: pattern missing: {old[:60]!r}')
            continue
        s = s.replace(old, new, 1)
    io.open(path, 'w', encoding='utf-8').write(s)
    print('ok', path)

# 1) Agnes 提供商改名 + 迁移已有名称
patch('lib/services/settings_service.dart', [
    ("const kAgnesPresetName = 'Agnes 中国站';",
     "const kAgnesPresetName = 'Agnes提供商';"),
    ('''    // 默认只添加 Agnes 中国站；其他提供商仅在“添加提供商”预设里出现
    final seeded = _sp.getBool('presetsSeeded') ?? false;''',
     '''    // 默认只添加 Agnes提供商；其他提供商仅在“添加提供商”预设里出现
    // 旧名称统一迁移
    for (var i = 0; i < providers.length; i++) {
      if (providers[i].name == 'Agnes 中国站' ||
          providers[i].name == 'Agnes（免费额度）' ||
          providers[i].name == 'Agnes') {
        providers[i].name = kAgnesPresetName;
      }
    }
    final seeded = _sp.getBool('presetsSeeded') ?? false;'''),
    ("'Agnes 完全免费 · 不限额度。登录官网即可免费领取 AI Key',",
     "'Agnes 完全免费 · 不限额度。登录官网即可免费领取 API Key',"),
], must=False)

# 免费文案在 settings_page
patch('lib/pages/settings_page.dart', [
    ('Agnes 完全免费 · 不限额度。登录官网即可免费领取 AI Key',
     'Agnes 完全免费 · 不限额度。登录官网即可免费领取 API Key'),
    ('默认提供商 Agnes 支持免费获取 AI Key，登录后即可领取',
     '默认提供商 Agnes提供商：完全免费、不限额度'),
], must=False)

# 2) 字重统一：w500 → w600（平台字体渲染一致性）
for f in glob.glob('lib/**/*.dart', recursive=True):
    s = io.open(f, encoding='utf-8').read()
    if 'FontWeight.w500' in s:
        s = s.replace('FontWeight.w500', 'FontWeight.w600')
        io.open(f, 'w', encoding='utf-8').write(s)
        print('w500->w600', f)

# 3) 液态玻璃：降模糊、提不透明度 → 清晰不朦胧
patch('lib/widgets/glass.dart', [
    ('filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),',
     'filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),'),
    ('''                color: color ??
                    (dark
                        ? Colors.white.withValues(alpha: 0.09)
                        : Colors.white.withValues(alpha: 0.5)),''',
     '''                color: color ??
                    (dark
                        ? const Color(0xFF161C28).withValues(alpha: 0.82)
                        : Colors.white.withValues(alpha: 0.82)),'''),
    ('''                  colors: [
                    Colors.white.withValues(alpha: dark ? 0.14 : 0.35),
                    Colors.white.withValues(alpha: 0.02),
                    Colors.white.withValues(alpha: dark ? 0.06 : 0.12),
                  ],
                  stops: const [0, 0.55, 1],''',
     '''                  colors: [
                    Colors.white.withValues(alpha: dark ? 0.08 : 0.22),
                    Colors.white.withValues(alpha: 0.0),
                    Colors.white.withValues(alpha: dark ? 0.03 : 0.08),
                  ],
                  stops: const [0, 0.55, 1],'''),
])

# 4) 思考深度：预设扩展 + 自定义（档位字符串自由填写）
patch('lib/pages/settings_page.dart', [
    ('''                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'low', child: Text('低 low')),
                              PopupMenuItem(
                                  value: 'medium', child: Text('中 medium')),
                              PopupMenuItem(value: 'high', child: Text('高 high')),
                            ],''',
     '''                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'on', child: Text('开 on')),
                              PopupMenuItem(value: 'low', child: Text('低 low')),
                              PopupMenuItem(
                                  value: 'medium', child: Text('中 medium')),
                              PopupMenuItem(value: 'high', child: Text('高 high')),
                              PopupMenuItem(
                                  value: 'ultra', child: Text('超高 ultra')),
                            ],'''),
], must=False)

print('core patches done')
