import io

p = 'lib/pages/intro/onboarding_page.dart'
s = io.open(p, encoding='utf-8').read()

# 嵌入模式支持
s = s.replace('''class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});''', '''class OnboardingPage extends StatefulWidget {
  final bool embedded; // 从设置重新浏览：结束后仅返回
  const OnboardingPage({super.key, this.embedded = false});''')

s = s.replace('''  Future<void> _finish() async {
    SettingsService.I.finishOnboarding();
    await EtsDataService.I.rescan();
    if (mounted) {
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeShell()));
    }
  }''', '''  Future<void> _finish() async {
    if (!widget.embedded) {
      SettingsService.I.finishOnboarding();
      await EtsDataService.I.rescan();
    }
    if (mounted) {
      if (widget.embedded) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeShell()));
      }
    }
  }''')

# 底部按钮：上一步 / 下一步（双按钮）
old_btn = '''            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: () {
                    if (_page == _pages.length - 1) {
                      _finish();
                    } else {
                      _ctrl.nextPage(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOut);
                    }
                  },
                  child: Text(
                      _page == _pages.length - 1 ? '开始使用' : '下一步'),
                ),
              ),
            ),'''
new_btn = '''            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  if (_page > 0)
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () => _ctrl.previousPage(
                              duration: const Duration(milliseconds: 280),
                              curve: Curves.easeOut),
                          child: const Text('上一步'),
                        ),
                      ),
                    ),
                  if (_page > 0) const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: () {
                          if (_page == _pages.length - 1) {
                            _finish();
                          } else {
                            _ctrl.nextPage(
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeOut);
                          }
                        },
                        child: Text(_page == _pages.length - 1
                            ? (widget.embedded ? '完成' : '开始使用')
                            : '下一步'),
                      ),
                    ),
                  ),
                ],
              ),
            ),'''
assert old_btn in s, 'button row not found'
s = s.replace(old_btn, new_btn, 1)

# 跳过按钮在嵌入模式下改为关闭
s = s.replace('''              child: TextButton(
                onPressed: _finish,
                child: const Text('跳过'),
              ),''', '''              child: TextButton(
                onPressed: _finish,
                child: Text(widget.embedded ? '关闭' : '跳过'),
              ),''')

io.open(p, 'w', encoding='utf-8').write(s)
print('onboarding ok')
