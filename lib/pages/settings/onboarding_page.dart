import 'package:flutter/material.dart';

import '../../services/ets_data_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/glass.dart';
import '../../app/home_shell.dart';

/// 首次启动新手教程：功能介绍 → 数据来源 → AI 配置 → 开始
/// 可随时跳过；完成后内置演示作业自动隐藏
class OnboardingPage extends StatefulWidget {
  final bool embedded; // 从设置重新浏览：结束后仅返回
  const OnboardingPage({super.key, this.embedded = false});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _ctrl = PageController();
  int _page = 0;

  static const _pages = [
    (
      Icons.assignment_rounded,
      '欢迎使用 E听说助手',
      '本地解析 E听说 客户端已下载的作业数据：'
          '模仿朗读、角色扮演、故事复述、对话跟读、单词跟读，'
          '答案、范文、评分关键词一站查看，支持背题模式。',
    ),
    (
      Icons.headphones_rounded,
      '精听与模拟考场',
      '逐句区间播放、倍速、A-B 循环；'
          '按原软件流程复现考试：播放 → 倒计时 → 录音 → 回放。',
    ),
    (
      Icons.auto_awesome,
      'AI 加持（可选）',
      '在设置里配置任意 OpenAI 兼容接口（默认提供商 Agnes 中国站，'
          '可免费领取额度）：智能解析、翻译、实时对话、悬浮窗快问；'
          '多模型优先级 + 故障自动切换。不配置也完全可用。',
    ),
    (
      Icons.folder_open_rounded,
      '数据在哪？',
      '电脑：默认扫描 %APPDATA%\\ETS；'
          '手机：需要 Root 或 Shizuku 提取权限（设置里有引导）。'
          '首次启动已内置两份演示作业供参考，进入正式使用后自动隐藏，'
          '也可以在设置里随时打开。',
    ),
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (!widget.embedded) {
      SettingsService.I.finishOnboarding();
      SettingsService.I.requestTour(value: true); // 接着播放页面内互动教程
      await EtsDataService.I.rescan();
    }
    if (mounted) {
      if (widget.embedded) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeShell()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 引导页也是控制层/内容层混排，补上背景墙，与主应用同一套视觉
    return GlassScaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: Text(widget.embedded ? '关闭' : '跳过'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _ctrl,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  final (icon, title, body) = _pages[i];
                  // 横屏/矮窗口下内容装不下，按可用高度收缩并允许滚动
                  return LayoutBuilder(
                    builder: (context, c) {
                      final compact = c.maxHeight < 320;
                      final iconBox = compact ? 56.0 : 96.0;
                      return SingleChildScrollView(
                        child: Padding(
                          padding: EdgeInsets.all(compact ? 16 : 32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: iconBox,
                                height: iconBox,
                                decoration: BoxDecoration(
                                  color: cs.primaryContainer.withValues(
                                    alpha: 0.6,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(
                                  icon,
                                  size: iconBox * 0.5,
                                  color: cs.primary,
                                ),
                              ),
                              SizedBox(height: compact ? 12 : 24),
                              Text(
                                title,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              SizedBox(height: compact ? 8 : 16),
                              Text(
                                body,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(height: 1.7),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages.length; i++)
                  Container(
                    width: i == _page ? 20 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: i == _page ? cs.primary : cs.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
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
                            curve: Curves.easeOut,
                          ),
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
                              curve: Curves.easeOut,
                            );
                          }
                        },
                        child: Text(
                          _page == _pages.length - 1
                              ? (widget.embedded ? '完成' : '开始使用')
                              : '下一步',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
