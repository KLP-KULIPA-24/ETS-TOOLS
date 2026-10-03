import io

# 1) settings_service: grade/region
p = 'lib/services/settings_service.dart'
s = io.open(p, encoding='utf-8').read()
assert 'String grade' not in s, 'grade already added'

s = s.replace('''  // ---- 作业管理：已完成 / 已删除（按目录 key）----''',
'''  // ---- 考试信息（格式匹配：初中/高中、地区）----
  String grade = ''; // 初一~高三
  String region = ''; // 如 广东东莞

  void setExamInfo({String? grade, String? region}) {
    if (grade != null) {
      this.grade = grade;
      _sp.setString('grade', grade);
    }
    if (region != null) {
      this.region = region;
      _sp.setString('region', region);
    }
    notifyListeners();
  }

  bool get isJunior =>
      grade == '初一' || grade == '初二' || grade == '初三';

  // ---- 作业管理：已完成 / 已删除（按目录 key）----''', 1)

s = s.replace('''    showDemoData = _sp.getBool('showDemoData') ?? true;
    useRoot = _sp.getBool('useRoot') ?? true;''',
'''    showDemoData = _sp.getBool('showDemoData') ?? true;
    grade = _sp.getString('grade') ?? '';
    region = _sp.getString('region') ?? '';
    useRoot = _sp.getBool('useRoot') ?? true;''', 1)

io.open(p, 'w', encoding='utf-8').write(s)
print('service ok')

# 2) settings_page: 考试信息卡
p2 = 'lib/pages/settings_page.dart'
s2 = io.open(p2, encoding='utf-8').read()
assert '考试信息' not in s2, 'exam card already added'

anchor = '''          // ---- 外观 ----
          GlassContainer(
            key: _kAppearance,'''
card = '''          // ---- 考试信息（格式匹配：初中/高中、地区）----
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
                        width: 56,
                        child: Text('年级',
                            style: TextStyle(fontSize: 13))),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue:
                            s.grade.isEmpty ? null : s.grade,
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
                        width: 56,
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
                  '年级决定初中/高中格式匹配；批量生成标题也会参考年级与地区。',
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
assert anchor in s2, 'appearance anchor not found'
s2 = s2.replace(anchor, card, 1)

io.open(p2, 'w', encoding='utf-8').write(s2)
print('exam card ok')

# 3) 批量标题 prompt 带年级/地区
p3 = 'lib/services/title_batch_service.dart'
s3 = io.open(p3, encoding='utf-8').read()
if 's.grade' not in s3:
    old3 = '''      final sb = StringBuffer();
      sb.writeln('以下是若干英语听说作业的编号和内容片段。');'''
    new3 = '''      final sb = StringBuffer();
      sb.writeln('以下是若干英语听说作业的编号和内容片段。');
      if (s.grade.isNotEmpty || s.region.isNotEmpty) {
        sb.writeln('背景：${s.grade.isEmpty ? '' : s.grade}'
            '${s.region.isEmpty ? '' : '（${s.region}）'}英语听说考试。');
      }'''
    assert old3 in s3, 'batch prompt anchor not found'
    s3 = s3.replace(old3, new3, 1)
    io.open(p3, 'w', encoding='utf-8').write(s3)
print('batch prompt ok')
