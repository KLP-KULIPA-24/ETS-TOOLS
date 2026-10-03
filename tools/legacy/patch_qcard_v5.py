import io

p = 'lib/pages/detail/typed_views.dart'
s = io.open(p, encoding='utf-8').read()

# QCard：按 ask 类型重写答案逻辑
old = '''  @override
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
      answer.trim().isNotEmpty && answer.trim() == v.trim();'''
new = '''  @override
  void initState() {
    super.initState();
    final q = widget.q;
    // 三问（中文提示）：std = 你要问的英文问句；answer = 对话中的答案
    // 五答（英文提问）：answer/std = 答案
    final askIsChinese = RegExp(r'[\\u4e00-\\u9fff]').hasMatch(q.ask);
    _isAskType = askIsChinese;
    if (askIsChinese) {
      _askVariants = [
        for (final st in q.std)
          if (st.value.trim().isNotEmpty) st.value.trim(),
      ];
      _answerCandidates = [
        if (q.answer.trim().isNotEmpty &&
            !_askVariants.contains(q.answer.trim()))
          q.answer.trim(),
      ];
    } else {
      _askVariants = [];
      _answerCandidates = [
        if (q.answer.trim().isNotEmpty) q.answer.trim(),
        for (final st in q.std)
          if (st.value.trim().isNotEmpty &&
              st.value.trim() != q.answer.trim())
            st.value.trim(),
      ];
      _answerCandidates.sort((a, b) => a.length.compareTo(b.length)); // 最短优先
    }
    _shortAnswer = _answerCandidates.isEmpty ? '' : _answerCandidates.first;
  }

  late bool _isAskType;
  late List<String> _askVariants; // 三问：英文问句变体
  late List<String> _answerCandidates; // 答案候选'''
assert old in s, 'initState not found'
s = s.replace(old, new, 1)

# build 中变量与区块
s = s.replace('''    final askSentence = q.std.isNotEmpty ? q.std.first.value.trim() : '';
    final sameAsAnswer =
        askSentence.isNotEmpty && askSentence == answerText.trim();
    final isAsk = q.role == 'a';
''', '''    final isAsk = _isAskType;
''')

old_ask = '''          // 三问：英文问句（std 参考）；与参考答案相同时只显示一个区
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
          ],
          if (hasMore) ...['''
new_ask = '''          // 三问：你要问的英文问句（std 第一条）+ 更多问法
          if (isAsk && _askVariants.isNotEmpty && hide == false) ...[
            const SizedBox(height: 6),
            Text('你要问的英文问题（参考）',
                style: TextStyle(fontSize: 11, color: cs.outline)),
            const SizedBox(height: 3),
            SmartSelectableText(_askVariants.first,
                style: TextStyle(
                    height: 1.5,
                    fontSize: 13.5,
                    color: cs.tertiary,
                    fontWeight: FontWeight.w600)),
            if (_askVariants.length > 1) ...[
              const SizedBox(height: 4),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _moreVariants = !_moreVariants),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _moreVariants
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 15,
                        color: cs.primary,
                      ),
                      const SizedBox(width: 3),
                      Text('更多问法（共 ${_askVariants.length} 个）',
                          style:
                              TextStyle(fontSize: 11.5, color: cs.primary)),
                    ],
                  ),
                ),
              ),
              if (_moreVariants)
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
                        for (var i = 1; i < _askVariants.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${i}. ',
                                    style: TextStyle(
                                        fontSize: 12, color: cs.outline)),
                                Expanded(
                                  child: SmartSelectableText(
                                      _askVariants[i],
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
            ],
          ],
          // 答案：三问=对话中的答案；五答=最短参考答案
          if (isAsk && answerText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('对话中的答案',
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
          if (!isAsk && answerText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('参考答案（最短）',
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
          if (!isAsk && hasMore) ...['''
assert old_ask in s, 'ask block v2 not found'
s = s.replace(old_ask, new_ask, 1)

# hasMore 仅五答用；更多变体状态字段
s = s.replace('''  bool _moreAnswers = false;
  bool _showKeywords = false;''', '''  bool _moreAnswers = false;
  bool _moreVariants = false;
  bool _showKeywords = false;''')

io.open(p, 'w', encoding='utf-8').write(s)
print('qcard v5 ok')
