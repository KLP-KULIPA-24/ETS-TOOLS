import io

p = 'lib/pages/capture_page.dart'
s = io.open(p, encoding='utf-8').read()

old = '''          // 拦截规则
          GlassContainer('''
new = '''          // 成绩规则
          GlassContainer(
            radius: 18,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.military_tech_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text('修改指定成绩',
                            style: Theme.of(context).textTheme.titleSmall)),
                    Switch(
                      value:
                          context.watch<SettingsService>().captureScoreOn,
                      onChanged: (v) {
                        context
                            .read<SettingsService>()
                            .setCaptureScore(on: v);
                        setState(() {});
                      },
                    ),
                  ],
                ),
                SizedBox(
                  height: 42,
                  child: TextField(
                    decoration: const InputDecoration(
                        isDense: true,
                        labelText: '目标成绩（例：98.5 或 A+）'),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (v) => context
                        .read<SettingsService>()
                        .setCaptureScore(value: v),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 完成时间规则
          GlassContainer(
            radius: 18,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.timer_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text('修改完成时间',
                            style: Theme.of(context).textTheme.titleSmall)),
                    Switch(
                      value: context.watch<SettingsService>().captureTimeOn,
                      onChanged: (v) {
                        context
                            .read<SettingsService>()
                            .setCaptureTime(on: v);
                        setState(() {});
                      },
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('提前量（分钟）'),
                    Expanded(
                      child: Slider(
                        value: context
                            .watch<SettingsService>()
                            .captureTimeOffsetMin
                            .toDouble()
                            .clamp(0, 120),
                        max: 120,
                        divisions: 24,
                        label: '提前 ${context.watch<SettingsService>().captureTimeOffsetMin} 分钟',
                        onChanged: (v) => context
                            .read<SettingsService>()
                            .setCaptureTime(offsetMin: v.round()),
                      ),
                    ),
                    Text(
                        '${context.watch<SettingsService>().captureTimeOffsetMin} 分钟',
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 拦截规则
          GlassContainer('''
assert old in s, 'capture anchor not found'
s = s.replace(old, new, 1)

if 'package:provider/provider.dart' not in s:
    s = s.replace("import 'package:flutter/material.dart';",
                  "import 'package:flutter/material.dart';\nimport 'package:provider/provider.dart';")

io.open(p, 'w', encoding='utf-8').write(s)
print('capture rules ok')
