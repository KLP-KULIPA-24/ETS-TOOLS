import io

# ============ 1) 设置页 AI 区排版 ============
p = 'lib/pages/settings_page.dart'
s = io.open(p, encoding='utf-8').read()

# 模型卡 chips 左对齐（不居中）
s = s.replace('''              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,''',
'''              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Wrap(
                  alignment: WrapAlignment.start,
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,''')

# 调用策略区：整齐两列表单
old_policy = '''          Text('调用策略（防限流 / 失败重试）',
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  keyboardType: TextInputType.number,
                  controller: TextEditingController(
                      text: '${s.aiRetryCount}')
                    ..selection = TextSelection.collapsed(
                        offset: '${s.aiRetryCount}'.length),
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: '失败自动重试次数',
                  ),
                  style: const TextStyle(fontSize: 13),
                  onChanged: (v) => s.setAiPolicy(
                      retryCount: int.tryParse(v) ?? s.aiRetryCount),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  keyboardType: TextInputType.number,
                  controller:
                      TextEditingController(text: '${s.aiRatePerMin}')
                        ..selection = TextSelection.collapsed(
                            offset: '${s.aiRatePerMin}'.length),
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: '速率限制（次/分钟）',
                    helperText: '0=不限',
                  ),
                  style: const TextStyle(fontSize: 13),
                  onChanged: (v) => s.setAiPolicy(
                      ratePerMin: int.tryParse(v) ?? s.aiRatePerMin),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('免费额度建议限速 10 次/分钟（Agnes 免费个人用户默认约 1 分钟 10 次）。',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.outline)),
'''
new_policy = '''          Text('调用策略（防限流 / 失败重试）',
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 150,
                child: TextField(
                  keyboardType: TextInputType.number,
                  controller: TextEditingController(
                      text: '${s.aiRetryCount}'),
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: '失败重试次数',
                    hintText: '1',
                  ),
                  style: const TextStyle(fontSize: 13),
                  onChanged: (v) => s.setAiPolicy(
                      retryCount: int.tryParse(v) ?? s.aiRetryCount),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 150,
                child: TextField(
                  keyboardType: TextInputType.number,
                  controller:
                      TextEditingController(text: '${s.aiRatePerMin}'),
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: '速率限制（次/分）',
                    hintText: '0 = 不限',
                  ),
                  style: const TextStyle(fontSize: 13),
                  onChanged: (v) => s.setAiPolicy(
                      ratePerMin: int.tryParse(v) ?? s.aiRatePerMin),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('免费额度建议限速 10 次/分钟',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.outline)),
              ),
            ],
          ),
'''
assert old_policy in s, 'policy block not found'
s = s.replace(old_policy, new_policy, 1)

io.open(p, 'w', encoding='utf-8').write(s)
print('settings ai layout ok')

# ============ 2) 修改栏：目标成绩文案 + 删除拦截规则块 ============
p = 'lib/pages/capture_page.dart'
s = io.open(p, encoding='utf-8').read()

s = s.replace("labelText: '目标成绩（例：98.5 或 A+）')",
              "labelText: '目标成绩（分），例如：60')")

# 删除拦截规则块（从注释到下一个 const SizedBox(height: 14) 之前）
start = s.find('          // 拦截规则\n')
end = s.find('          const SizedBox(height: 14),', start)
assert start >= 0 and end > start, 'rules block not found'
s = s[:start] + s[end + len('          const SizedBox(height: 14),\n'):]

# 删除 rules 状态字段与 _addRule 方法（不再使用）
import re
s = s.replace('''  final rules = <({String match, String action, bool on})>[
    (match: '*/score/submit*', action: '替换成绩字段', on: false),
    (match: '*/exam/time*', action: '延长时间戳', on: false),
  ];
''', '')
# _addRule 方法整体删除
add_start = s.find('  Future<void> _addRule(BuildContext context) async {')
if add_start >= 0:
    add_end = s.find('\n  }\n', add_start)
    s = s[:add_start] + s[add_end + 4:]

io.open(p, 'w', encoding='utf-8').write(s)
print('capture page ok')

# ============ 3) 三问五答排版：去重复 + 关键词折叠 ============
p = 'lib/pages/detail/typed_views.dart'
s = io.open(p, encoding='utf-8').read()

# _QCardState 增加关键词折叠状态
s = s.replace('''class _QCardState extends State<_QCard> {
  bool _moreAnswers = false;''', '''class _QCardState extends State<_QCard> {
  bool _moreAnswers = false;
  bool _showKeywords = false;''')

# 三问问句/答案去重：相同时只显示一个区
old_ask = '''          // 三问：显示要用的英文问句（std 参考问句）
          if (isAsk && q.std.isNotEmpty && hide == false) ...[
            const SizedBox(height: 6),
            Text('你要问的英文问题（参考）',
                style: TextStyle(fontSize: 11, color: cs.outline)),
            const SizedBox(height: 3),
            SmartSelectableText(q.std.first.value,
                style: TextStyle(
                    height: 1.5,
                    fontSize: 13.5,
                    color: cs.tertiary,
                    fontWeight: FontWeight.w600)),
          ],
          if (answerText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(isAsk ? '参考答案' : '参考答案（最短）',
                style: TextStyle(fontSize: 11, color: cs.outline)),
            const SizedBox(height: 3),
            hide
                ? BlurReveal(
                    child: SmartSelectableText(answerText,
                        style: const TextStyle(height: 1.6, fontSize: 15)))
                : SmartSelectableText(answerText,
                    style: TextStyle(
                        height: 1.6,
                        fontSize: 15,
                        color: cs.primary,
                        fontWeight: FontWeight.w600)),
          ],'''
new_ask = '''          // 三问：英文问句（std 参考）；与参考答案相同时只显示一个区
          final askSentence =
              q.std.isNotEmpty ? q.std.first.value.trim() : '';
          final sameAsAnswer =
              askSentence.isNotEmpty && askSentence == answerText.trim();
          if (isAsk &&
              askSentence.isNotEmpty &&
              !sameAsAnswer &&
              hide == false) ...[
            const SizedBox(height: 6),
            Text('你要问的英文问题（参考）',
                style: TextStyle(fontSize: 11, color: cs.outline)),
            const SizedBox(height: 3),
            SmartSelectableText(askSentence,
                style: TextStyle(
                    height: 1.5,
                    fontSize: 13.5,
                    color: cs.tertiary,
                    fontWeight: FontWeight.w600)),
          ],
          if (answerText.isNotEmpty && !sameAsAnswer) ...[
            const SizedBox(height: 8),
            Text(isAsk ? '参考答案' : '参考答案（最短）',
                style: TextStyle(fontSize: 11, color: cs.outline)),
            const SizedBox(height: 3),
            hide
                ? BlurReveal(
                    child: SmartSelectableText(answerText,
                        style: const TextStyle(height: 1.6, fontSize: 15)))
                : SmartSelectableText(answerText,
                    style: TextStyle(
                        height: 1.6,
                        fontSize: 15,
                        color: cs.primary,
                        fontWeight: FontWeight.w600)),
          ],'''
assert old_ask in s, 'ask/answer block not found'
s = s.replace(old_ask, new_ask, 1)

# 评分关键词默认折叠
old_kw = '''          if (q.keywordList.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final k in q.keywordList)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(k,
                        style: TextStyle(
                            fontSize: 11, color: cs.onSecondaryContainer)),
                  ),
              ],
            ),
          ],'''
new_kw = '''          if (q.keywordList.isNotEmpty) ...[
            const SizedBox(height: 4),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _showKeywords = !_showKeywords),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _showKeywords
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 15,
                      color: cs.outline,
                    ),
                    const SizedBox(width: 3),
                    Text('评分关键词 · ${q.keywordList.length}',
                        style: TextStyle(fontSize: 11.5, color: cs.outline)),
                  ],
                ),
              ),
            ),
            if (_showKeywords)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final k in q.keywordList)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: cs.secondaryContainer.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(k,
                            style: TextStyle(
                                fontSize: 11, color: cs.onSecondaryContainer)),
                      ),
                  ],
                ),
              ),
          ],'''
assert old_kw in s, 'keywords block not found'
s = s.replace(old_kw, new_kw, 1)

io.open(p, 'w', encoding='utf-8').write(s)
print('qcard layout ok')
