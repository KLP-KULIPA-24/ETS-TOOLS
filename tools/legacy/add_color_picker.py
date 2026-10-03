import io

p = 'lib/pages/settings_page.dart'
s = io.open(p, encoding='utf-8').read()

# 在 _hueOf 前插入调色窗口方法
anchor = '  double _hueOf(int argb) {'
picker = '''  Future<void> _openColorPicker(BuildContext context) async {
    final s = context.read<SettingsService>();
    final picked = await showDialog<Color>(
      context: context,
      builder: (context) => ColorPickerDialog(initial: Color(s.accentValue)),
    );
    if (picked != null) {
      s.setAccent(picked.toARGB32(), custom: true);
    }
  }

'''
assert anchor in s, 'hue anchor not found'
s = s.replace(anchor, picker + anchor, 1)

# 去掉不再使用的 _hueOf
old_hue = '''  double _hueOf(int argb) {
    final hsv = HSVColor.fromColor(Color(argb));
    return hsv.hue;
  }

'''
assert old_hue in s, 'hueOf not found'
s = s.replace(old_hue, '', 1)

io.open(p, 'w', encoding='utf-8').write(s)
print('picker wired')
