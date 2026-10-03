import io

# 1) 修复 _AndroidExtractCardState.build 的 s 引用（上次被中断）
p = 'lib/pages/settings_page.dart'
s = io.open(p, encoding='utf-8').read()

old = '''  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canExtract = ((_rootState == 'true') && s.useRoot) ||
        ((_shizuku == true) && s.useShizuku);'''
new = '''  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    final cs = Theme.of(context).colorScheme;
    final canExtract = ((_rootState == 'true') && s.useRoot) ||
        ((_shizuku == true) && s.useShizuku);'''
assert old in s, 'extract build not found'
s = s.replace(old, new, 1)

# 2) 考试信息卡（年级/地区）插入外观卡之前
anchor = '''          // ---- 外观 ----
          GlassContainer(
            key: _kAppearance,'''
exam_card = '''          // ---- 考试信息（用于格式匹配：初中/高中）----
          GlassContainer(
            radius: 18,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cardTitle(context, '考试信息（格式匹配）',
                    Icons.school_outlined),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const SizedBox(
                        width: 60,
                        child: Text('年级',
                            style: TextStyle(fontSize: 13))),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: s.grade.isEmpty ? null : s.grade,
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: '选择年级',
                        ),
                        items: const [
                          for (final g in [
                            '初一', '初二', '初三',
                            '高一', '高二', '高三',
                          ])
                            DropdownMenuItem(value: g, child: Text(g)),
                        ],
                        onChanged: (v) =>
                            s.setExamInfo(grade: v ?? ''),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const SizedBox(
                        width: 60,
                        child: Text('地区',
                            style: TextStyle(fontSize: 13))),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue:
                            s.region.isEmpty ? null : s.region,
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: '选择地区（可自定义）',
                        ),
                        items: [
                          for (final r in const [
                            '广东东莞', '广东广州', '广东深圳',
                            '广东其他', '北京', '上海', '其他地区',
                          ])
                            DropdownMenuItem(value: r, child: Text(r)),
                        ],
                        onChanged: (v) =>
                            s.setExamInfo(region: v ?? ''),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '年级决定初中/高中格式匹配；标题批量生成也会参考年级与地区。',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.outline),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ---- 外观 ----
          GlassContainer(
            key: _kAppearance,'''
assert anchor in s, 'appearance anchor not found'
s = s.replace(anchor, exam_card, 1)

io.open(p, 'w', encoding='utf-8').write(s)
print('exam info card ok')
