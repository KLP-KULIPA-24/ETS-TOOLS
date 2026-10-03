import io

# ---------- 1) 设置页：考试信息卡移到 数据目录 之后 + 全国地区列表 ----------
p = 'lib/pages/settings_page.dart'
s = io.open(p, encoding='utf-8').read()

# 摘出考试信息卡
start_marker = '          // ---- 考试信息（格式匹配：初中/高中、地区）----\n'
end_marker = '          // ---- 外观 ----\n'
st = s.find(start_marker)
en = s.find(end_marker)
assert st >= 0 and en > st, 'exam card not found'
exam_block = s[st:en]
s = s[:st] + s[en:]

# 插到 关于 之前（数据目录之后）
anchor_about = '          // ---- 关于 ----\n'
ia = s.find(anchor_about)
assert ia >= 0, 'about anchor not found'
s = s[:ia] + exam_block + s[ia:]

# 地区列表：全国省级 + 主要城市 + 自定义
old_items = '''                        items: [
                          for (final r in const [
                            '广东东莞', '广东广州', '广东深圳',
                            '广东其他', '北京', '上海', '其他地区',
                          ])
                            DropdownMenuItem(value: r, child: Text(r)),
                        ],
                        onChanged: (v) =>
                            s.setExamInfo(region: v ?? ''),'''
new_items = '''                        items: [
                          for (final r in kChinaRegions)
                            DropdownMenuItem(value: r, child: Text(r)),
                          if (s.region.isNotEmpty &&
                              !kChinaRegions.contains(s.region))
                            DropdownMenuItem(
                                value: s.region, child: Text(s.region)),
                          const DropdownMenuItem(
                              value: '__custom__', child: Text('自定义…')),
                        ],
                        onChanged: (v) async {
                          if (v == '__custom__') {
                            final ctrl = TextEditingController(
                                text: s.region);
                            final custom = await showDialog<String>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('自定义地区'),
                                content: TextField(
                                  controller: ctrl,
                                  autofocus: true,
                                  decoration: const InputDecoration(
                                      labelText: '地区（如 广东东莞）'),
                                ),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context),
                                      child: const Text('取消')),
                                  FilledButton(
                                      onPressed: () => Navigator.pop(
                                          context, ctrl.text.trim()),
                                      child: const Text('确定')),
                                ],
                              ),
                            );
                            if (custom != null && custom.isNotEmpty) {
                              s.setExamInfo(region: custom);
                            }
                            return;
                          }
                          s.setExamInfo(region: v ?? '');
                        },'''
assert old_items in s, 'region items not found'
s = s.replace(old_items, new_items, 1)

io.open(p, 'w', encoding='utf-8').write(s)
print('settings region ok')

# ---------- 2) 全国地区常量 ----------
p2 = 'lib/services/settings_service.dart'
s2 = io.open(p2, encoding='utf-8').read()
if 'kChinaRegions' not in s2:
    s2 = s2.replace("const kAgnesLoginUrl = 'https://platform.agnes-ai.cn/login';",
'''const kAgnesLoginUrl = 'https://platform.agnes-ai.cn/login';

/// 全国地区（省级 + 主要城市）
const kChinaRegions = <String>[
  '北京', '天津', '上海', '重庆',
  '广东广州', '广东深圳', '广东东莞', '广东佛山', '广东珠海',
  '广东中山', '广东惠州', '广东江门', '广东汕头', '广东湛江', '广东其他',
  '江苏南京', '江苏苏州', '江苏无锡', '江苏其他',
  '浙江杭州', '浙江宁波', '浙江温州', '浙江其他',
  '山东济南', '山东青岛', '山东其他',
  '福建福州', '福建厦门', '福建其他',
  '四川成都', '四川其他',
  '湖北武汉', '湖北其他',
  '湖南长沙', '湖南其他',
  '河南郑州', '河南其他',
  '河北石家庄', '河北其他',
  '山西太原', '山西其他',
  '陕西西安', '陕西其他',
  '安徽合肥', '安徽其他',
  '江西南昌', '江西其他',
  '辽宁沈阳', '辽宁大连', '辽宁其他',
  '吉林长春', '吉林其他',
  '黑龙江哈尔滨', '黑龙江其他',
  '广西南宁', '广西桂林', '广西其他',
  '云南昆明', '云南其他',
  '贵州贵阳', '贵州其他',
  '海南海口', '海南其他',
  '甘肃兰州', '甘肃其他',
  '青海西宁', '宁夏银川', '新疆乌鲁木齐', '西藏拉萨',
  '内蒙古呼和浩特', '其他地区',
];''')
    io.open(p2, 'w', encoding='utf-8').write(s2)
print('regions ok')
