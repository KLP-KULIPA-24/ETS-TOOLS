import io

# ---------- 1) settings_service：省→市 级联数据 ----------
p = 'lib/services/settings_service.dart'
s = io.open(p, encoding='utf-8').read()

# 用 kRegionMap 替换 kChinaRegions
start = s.find('/// 全国地区（省级 + 主要城市）\nconst kChinaRegions = <String>[')
end = s.find("];", start) + 2
assert start >= 0 and end > start, 'kChinaRegions not found'
region_map = '''/// 地区级联：省 → 市
const kRegionMap = <String, List<String>>{
  '北京市': ['北京市'],
  '天津市': ['天津市'],
  '上海市': ['上海市'],
  '重庆市': ['重庆市'],
  '广东省': ['东莞市', '广州市', '深圳市', '佛山市', '珠海市', '中山市',
    '惠州市', '江门市', '汕头市', '湛江市', '肇庆市', '揭阳市', '其他'],
  '江苏省': ['南京市', '苏州市', '无锡市', '常州市', '南通市', '其他'],
  '浙江省': ['杭州市', '宁波市', '温州市', '金华市', '其他'],
  '山东省': ['济南市', '青岛市', '烟台市', '潍坊市', '其他'],
  '福建省': ['福州市', '厦门市', '泉州市', '其他'],
  '四川省': ['成都市', '绵阳市', '其他'],
  '湖北省': ['武汉市', '宜昌市', '其他'],
  '湖南省': ['长沙市', '株洲市', '其他'],
  '河南省': ['郑州市', '洛阳市', '其他'],
  '河北省': ['石家庄市', '唐山市', '其他'],
  '山西省': ['太原市', '其他'],
  '陕西省': ['西安市', '其他'],
  '安徽省': ['合肥市', '芜湖市', '其他'],
  '江西省': ['南昌市', '赣州市', '其他'],
  '辽宁省': ['沈阳市', '大连市', '其他'],
  '吉林省': ['长春市', '其他'],
  '黑龙江省': ['哈尔滨市', '其他'],
  '广西壮族自治区': ['南宁市', '桂林市', '其他'],
  '云南省': ['昆明市', '其他'],
  '贵州省': ['贵阳市', '其他'],
  '海南省': ['海口市', '三亚市', '其他'],
  '甘肃省': ['兰州市', '其他'],
  '青海省': ['西宁市', '其他'],
  '宁夏回族自治区': ['银川市', '其他'],
  '新疆维吾尔自治区': ['乌鲁木齐市', '其他'],
  '西藏自治区': ['拉萨市', '其他'],
  '内蒙古自治区': ['呼和浩特市', '其他'],
};'''
s = s[:start] + region_map + s[end:]
io.open(p, 'w', encoding='utf-8').write(s)
print('region map ok')

# ---------- 2) settings_page：考试卡改级联两框 ----------
p2 = 'lib/pages/settings_page.dart'
s2 = io.open(p2, encoding='utf-8').read()

# 保留年级行；地区行替换为 省/市 两框
old_region = s2[s2.find('                    const SizedBox(\n                        width: 56,\n                        child: Text(\'地区\''):]

# 定位地区部分整体（从 地区 Text 到该 Row 的结尾 '),' 前）——直接重写整个 Row 区域
row_start = s2.find('''                Row(
                  children: [
                    const SizedBox(
                        width: 56,
                        child: Text('年级',''')
row_end = s2.find('''                const SizedBox(height: 6),
                Text(
                  '年级决定初中/高中格式匹配''')
assert row_start >= 0 and row_end > row_start, 'exam row not found'

new_row = '''                Row(
                  children: [
                    const SizedBox(
                        width: 56,
                        child: Text('年级',
                            style: TextStyle(fontSize: 13))),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue:
                            s.grade.isEmpty ? null : s.grade,
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: '选择年级',
                        ),
                        items: [
                          for (final g in [
                            '初一', '初二', '初三',
                            '高一', '高二', '高三',
                          ])
                            DropdownMenuItem(value: g, child: Text(g)),
                        ],
                        onChanged: (v) =>
                            s.setExamInfo(grade: v ?? ''),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const SizedBox(
                        width: 56,
                        child: Text('省份',
                            style: TextStyle(fontSize: 13))),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _prov,
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: '选择省份',
                        ),
                        items: [
                          for (final prov in kRegionMap.keys)
                            DropdownMenuItem(
                                value: prov, child: Text(prov)),
                        ],
                        onChanged: (v) {
                          setState(() {
                            _prov = v;
                            _city = null;
                          });
                          if (v != null) {
                            final city = kRegionMap[v]!.first;
                            s.setExamInfo(region: v + city);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _city,
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: _prov == null ? '先选省份' : '选择城市',
                        ),
                        items: [
                          for (final c in (_prov == null
                              ? const <String>[]
                              : kRegionMap[_prov]!))
                            DropdownMenuItem(value: c, child: Text(c)),
                        ],
                        onChanged: _prov == null
                            ? null
                            : (v) {
                                if (v == null) return;
                                setState(() => _city = v);
                                s.setExamInfo(region: _prov! + v);
                              },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
'''
s2 = s2[:row_start] + new_row + s2[row_end:]

# State 增加省/市临时值
s2 = s2.replace('''  final _kData = GlobalKey();
  final _kAbout = GlobalKey();''','''  final _kData = GlobalKey();
  final _kAbout = GlobalKey();
  String? _prov;
  String? _city;''')

io.open(p2, 'w', encoding='utf-8').write(s2)
print('cascade ok')
