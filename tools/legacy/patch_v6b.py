import io

# 1) 录音按钮提示语（用户指定措辞）
p = 'lib/pages/detail/typed_views.dart'
s = io.open(p, encoding='utf-8').read()
s = s.replace("tip: '播放示例问题录音'),", "tip: '播放问题录音'),")
s = s.replace("tip: '播放示例答案录音'),", "tip: '播放答案录音'),")
s = s.replace("tip: '播放标准答案示范录音'),", "tip: '播放示例答案录音'),")
io.open(p, 'w', encoding='utf-8').write(s)
print('tips ok')

# 2) 对话持久化加固：用户消息立即落盘；加载用 clear+addAll 防重复/丢失
p2 = 'lib/pages/ai_chat_page.dart'
s2 = io.open(p2, encoding='utf-8').read()

s2 = s2.replace('''    AiChatService.I.load(widget.historyKey).then((m) {
      if (mounted) setState(() => _msgs.addAll(m));
      _jumpBottom();
    });''', '''    AiChatService.I.load(widget.historyKey).then((m) {
      if (!mounted) return;
      setState(() {
        _msgs
          ..clear()
          ..addAll(m);
      });
      _jumpBottom();
    });''')

s2 = s2.replace('''    setState(() {
      _msgs.add(msg);
      _pendingImages.clear();
      _ctrl.clear();
      _sending = true;
      _streamText = '';
    });
    _jumpBottom();''', '''    setState(() {
      _msgs.add(msg);
      _pendingImages.clear();
      _ctrl.clear();
      _sending = true;
      _streamText = '';
    });
    // 用户消息立即落盘，中途退出也不丢
    AiChatService.I.save(widget.historyKey, _msgs);
    _jumpBottom();''')

io.open(p2, 'w', encoding='utf-8').write(s2)
print('chat persist ok')
