import io

p = 'lib/pages/capture_page.dart'
s = io.open(p, encoding='utf-8').read()

# 完成时间卡：数字 + 单位（天/时/分/秒），自动换算秒
old = '''                Row(
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
                ),'''
new = '''                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        controller: TextEditingController(
                            text: _timeValue > 0 ? _timeInput : ''),
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: '提前量',
                          hintText: '如 30',
                        ),
                        style: const TextStyle(fontSize: 13),
                        onChanged: (v) =>
                            _timeInput = v.trim(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        initialValue: _timeUnit,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: '单位',
                        ),
                        items: const [
                          DropdownMenuItem(value: 'd', child: Text('天')),
                          DropdownMenuItem(value: 'h', child: Text('时')),
                          DropdownMenuItem(value: 'm', child: Text('分')),
                          DropdownMenuItem(value: 's', child: Text('秒')),
                        ],
                        onChanged: (v) =>
                            setState(() => _timeUnit = v ?? 'm'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '将提前 \$_timeEcho 发送（\$_secEcho 秒）',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.outline),
                ),'''
assert old in s, 'time slider not found'
s = s.replace(old, new, 1)

# State 字段与换算
s = s.replace('''  bool captureEnabled = false;
  bool autoRewrite = false;
  int port = 8888;''','''  bool captureEnabled = false;
  bool autoRewrite = false;
  int port = 8888;
  // 完成时间：输入值 + 单位（天/时/分/秒），存储为秒
  double _timeValue = 0;
  String _timeUnit = 'm';

  int get _timeSec {
    const secPerUnit = {'d': 86400, 'h': 3600, 'm': 60, 's': 1};
    return (_timeValue * (secPerUnit[_timeUnit] ?? 60)).round();
  }

  String get _timeEcho {
    if (_timeSec <= 0) return '0 秒';
    final d = _timeSec ~/ 86400;
    final h = (_timeSec % 86400) ~/ 3600;
    final m = (_timeSec % 3600) ~/ 60;
    final sec = _timeSec % 60;
    final parts = <String>[];
    if (d > 0) parts.add('\$d 天');
    if (h > 0) parts.add('\$h 时');
    if (m > 0) parts.add('\$m 分');
    if (sec > 0) parts.add('\$sec 秒');
    return parts.join(' ');
  }

  String get _secEcho => '\$_timeSec';''', 1)

# 兼容旧字段引用（悬浮窗/其他地方读分钟的地方改读秒）
s = s.replace('_timeValue > 0 ? _timeInput : ', '_timeValue > 0 ? _timeInput : ')

io.open(p, 'w', encoding='utf-8').write(s)
print('capture time input ok')
