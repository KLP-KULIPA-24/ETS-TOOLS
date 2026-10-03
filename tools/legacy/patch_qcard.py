import io

p = 'lib/pages/detail/typed_views.dart'
s = io.open(p, encoding='utf-8').read()

old = '''// ---------- 题目卡片（三问五答） ----------
class _QCard extends StatelessWidget {
  final EtsQuestion q;
  final bool hide;
  final String dir;

  const _QCard({required this.q, required this.hide, required this.dir});

  String _mp3(String f) => f.isEmpty ? '' : '$dir/material/$f';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isAsk = q.role == 'a';
    final answerText = q.answer.isNotEmpty
        ? q.answer
        : (q.std.isNotEmpty ? q.std.map((e) => e.value).join('\\n或 ') : '');
'''
assert old in s, 'qcard header not found'

new = '''// ---------- 题目卡片（三问五答） ----------
class _QCard extends StatefulWidget {
  final EtsQuestion q;
  final bool hide;
  final String dir;

  const _QCard({required this.q, required this.hide, required this.dir});

  @override
  State<_QCard> createState() => _QCardState();
}

class _QCardState extends State<_QCard> {
  bool _moreAnswers = false;
  late final String _shortAnswer; // 默认展示最短答案
  late final List<String> _allAnswers;

  @override
  void initState() {
    super.initState();
    final q = widget.q;
    _allAnswers = [
      if (q.answer.trim().isNotEmpty) q.answer.trim(),
      for (final st in q.std)
        if (st.value.trim().isNotEmpty &&
            !_allAnsContains(q.answer, st.value))
          st.value.trim(),
    ];
    _allAnswers.sort((a, b) => a.length.compareTo(b.length)); // 最短优先
    _shortAnswer = _allAnswers.isEmpty ? '' : _allAnswers.first;
  }

  static bool _allAnsContains(String answer, String v) =>
      answer.trim().isNotEmpty && answer.trim() == v.trim();

  String _mp3(String f) => f.isEmpty ? '' : '${widget.dir}/material/$f';

  @override
  Widget build(BuildContext context) {
    final q = widget.q;
    final hide = widget.hide;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isAsk = q.role == 'a';
    final answerText = _shortAnswer;
    final hasMore = _allAnswers.length > 1;
'''
s = s.replace(old, new, 1)

# 答案区：默认最短 + 更多展开（限高滚动）+ 英文问句（三问角色）
old_ans = '''          if (answerText.isNotEmpty) ...[
            const SizedBox(height: 8),
            hide
                ? BlurReveal(
                    child: EtsTextView(answerText,
                        style: const TextStyle(height: 1.6, fontSize: 15)))
                : EtsTextView(answerText,
                    style: TextStyle(
                        height: 1.6,
                        fontSize: 15,
                        color: cs.primary,
                        fontWeight: FontWeight.w600)),
          ],'''
new_ans = '''          // 三问：显示要用的英文问句（std 参考问句）
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
          ],
          if (hasMore) ...[
            const SizedBox(height: 6),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _moreAnswers = !_moreAnswers),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _moreAnswers
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 15,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      _moreAnswers
                          ? '收起其他答案'
                          : '更多答案（共 ${_allAnswers.length} 个）',
                      style: TextStyle(fontSize: 11.5, color: cs.primary),
                    ),
                  ],
                ),
              ),
            ),
            if (_moreAnswers)
              Container(
                margin: const EdgeInsets.only(top: 6),
                constraints: const BoxConstraints(maxHeight: 190),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < _allAnswers.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${i + 1}. ',
                                  style: TextStyle(
                                      fontSize: 12, color: cs.outline)),
                              Expanded(
                                child: SmartSelectableText(
                                    _allAnswers[i],
                                    style: const TextStyle(
                                        fontSize: 13, height: 1.5)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],'''
assert old_ans in s, 'answer block not found'
s = s.replace(old_ans, new_ans, 1)

io.open(p, 'w', encoding='utf-8').write(s)
print('qcard reworked')
