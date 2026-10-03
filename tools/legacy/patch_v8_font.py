import io, glob

# 3) 字重统一：页面/组件内 bold(700) → w600（Logo “E” 除外）
skip = ['main.dart']
for f in glob.glob('lib/**/*.dart', recursive=True):
    if any(f.endswith(x) for x in skip):
        continue
    s = io.open(f, encoding='utf-8').read()
    if 'FontWeight.bold' in s:
        s = s.replace('FontWeight.bold', 'FontWeight.w600')
        io.open(f, 'w', encoding='utf-8').write(s)
        print('bold->w600', f)

# 4) AI 设置调用策略排版：label 精简 + 提示合并
p = 'lib/pages/settings_page.dart'
s = io.open(p, encoding='utf-8').read()
old = '''          Text('调用策略（防限流 / 失败重试）',
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
new = '''          Text('调用策略（防限流 / 失败重试）',
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  keyboardType: TextInputType.number,
                  controller:
                      TextEditingController(text: '${s.aiRetryCount}'),
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: '失败重试次数',
                  ),
                  style: const TextStyle(fontSize: 13),
                  onChanged: (v) => s.setAiPolicy(
                      retryCount: int.tryParse(v) ?? s.aiRetryCount),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  keyboardType: TextInputType.number,
                  controller:
                      TextEditingController(text: '${s.aiRatePerMin}'),
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: '速率限制（次/分钟）',
                  ),
                  style: const TextStyle(fontSize: 13),
                  onChanged: (v) => s.setAiPolicy(
                      ratePerMin: int.tryParse(v) ?? s.aiRatePerMin),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('免费额度建议限速 10 次/分钟；0 = 不限速。',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.outline)),
'''
assert old in s, 'policy layout not found'
s = s.replace(old, new, 1)
io.open(p, 'w', encoding='utf-8').write(s)
print('policy layout ok')
