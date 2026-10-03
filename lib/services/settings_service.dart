import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'region_data.dart';

/// 界面风格
enum AppStyle { material, glass }

/// 布局模式：自动（平板左栏/手机底栏）/ 平板（模仿电脑）/ 手机
enum UiLayoutMode { auto, tablet, mobile }

/// 预设 AI 提供商（添加时可选；默认只添加 Agnes 中国站）
const kAiProviderPresets = <(String, String)>[
  ('Agnes 中国站', 'https://api.agnes-ai.cn/v1'),
  ('DeepSeek', 'https://api.deepseek.com/v1'),
  ('智谱 GLM', 'https://open.bigmodel.cn/api/paas/v4'),
  ('Kimi', 'https://api.moonshot.cn/v1'),
  ('通义千问', 'https://dashscope.aliyuncs.com/compatible-mode/v1'),
  ('OpenAI', 'https://api.openai.com/v1'),
];

/// Agnes 平台（免费领取 API Key 的入口）
const kAgnesLoginUrl = 'https://platform.agnes-ai.cn/';

/// Shizuku 下载：原版直链与国内镜像（v13.6.0 官方 release APK）
const kShizukuApkUrl =
    'https://github.com/RikkaApps/Shizuku/releases/download/v13.6.0/shizuku-v13.6.0.r1086.2650830c-release.apk';
const kShizukuMirrorUrl =
    'https://gh.xmly.dev/https://github.com/RikkaApps/Shizuku/releases/download/v13.6.0/shizuku-v13.6.0.r1086.2650830c-release.apk';

/// 地区级联：省 → 市（全国 34 省级 + 349 个地级行政区全量）
const kRegionMap = kRegionFull;
const kAgnesBaseUrl = 'https://api.agnes-ai.cn/v1';
const kAgnesPresetName = 'Agnes提供商';

/// 开源仓库（关于卡按钮 + 网页直连）
const kGithubRepoUrl = 'https://github.com/KLP-KULIPA-24/ETS-TOOLS';
const kGithubRepoLabel = 'github.com/KLP-KULIPA-24/ETS-TOOLS';

/// 对外版本号（固定 0.8，只递增 pubspec 的 build 号）。
/// 改这里时同步：pubspec.yaml / windows/installer.iss / 网页 V0.8 / web/docs/version.json
const kAppVersion = '0.8';

/// AI 服务提供商
class AiProvider {
  String id;
  String name;
  String baseUrl;
  String apiKey;
  AiProvider({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
  };

  static AiProvider fromJson(Map<String, dynamic> j) => AiProvider(
    id: '${j['id'] ?? ''}',
    name: '${j['name'] ?? ''}',
    baseUrl: '${j['baseUrl'] ?? ''}',
    apiKey: '${j['apiKey'] ?? ''}',
  );
}

/// 思考档位全集（不含 off——「关」由思考开关承担）
const kThinkingLevelOrder = ['on', 'low', 'medium', 'high', 'ultra', 'max'];

/// AI 模型（同一提供商可配多个）
/// 思考档位：id → 中文名（对话菜单/编辑器共用）
const kThinkingLevelLabels = {
  'off': '关',
  'on': '开',
  'low': '低',
  'medium': '中',
  'high': '高',
  'ultra': '超高',
  'max': '最高',
};

class AiModel {
  String id;
  String name;
  String model; // API 模型 ID
  String providerId;
  bool thinking; // 开启思考
  String thinkingLevel; // off / on / low / medium / high / ultra / max
  bool multimodal; // 支持图片输入
  List<String> thinkingLevels; // 本模型启用的思考档位（对话页按此顺序显示）
  int? maxContext; // 最大上下文（tokens），null = 不裁剪
  int? maxOutput; // 最大输出（tokens），null = 4096
  /// 本模型失败重试次数（默认 5，Agnes 免费额度的常规值）
  int retries;

  /// 本模型速率限制（次/分钟，0 = 不限速；默认 10）
  int ratePerMin;

  AiModel({
    required this.id,
    required this.name,
    required this.model,
    required this.providerId,
    this.thinking = false,
    this.thinkingLevel = 'medium',
    this.multimodal = false,
    this.thinkingLevels = const ['low', 'medium', 'high'],
    this.maxContext,
    this.maxOutput,
    this.retries = 5,
    this.ratePerMin = 10,
  });

  static const Object _unset = Object();

  /// [maxContext] / [maxOutput] / [thinkingLevels] 传 null 表示显式清除（区别于不传 = 保留）
  AiModel copyWith({
    String? id,
    String? name,
    String? model,
    String? providerId,
    bool? thinking,
    String? thinkingLevel,
    bool? multimodal,
    Object? thinkingLevels = _unset,
    Object? maxContext = _unset,
    Object? maxOutput = _unset,
    int? retries,
    int? ratePerMin,
  }) => AiModel(
    id: id ?? this.id,
    name: name ?? this.name,
    model: model ?? this.model,
    providerId: providerId ?? this.providerId,
    thinking: thinking ?? this.thinking,
    thinkingLevel: thinkingLevel ?? this.thinkingLevel,
    multimodal: multimodal ?? this.multimodal,
    thinkingLevels: thinkingLevels == _unset
        ? this.thinkingLevels
        : (thinkingLevels as List<String>?) ?? const [],
    maxContext: maxContext == _unset ? this.maxContext : maxContext as int?,
    maxOutput: maxOutput == _unset ? this.maxOutput : maxOutput as int?,
    retries: retries ?? this.retries,
    ratePerMin: ratePerMin ?? this.ratePerMin,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'model': model,
    'providerId': providerId,
    'thinking': thinking,
    'thinkingLevel': thinkingLevel,
    'multimodal': multimodal,
    'thinkingLevels': thinkingLevels,
    if (maxContext != null) 'maxContext': maxContext,
    if (maxOutput != null) 'maxOutput': maxOutput,
    'retries': retries,
    'ratePerMin': ratePerMin,
  };

  static AiModel fromJson(Map<String, dynamic> j) => AiModel(
    id: '${j['id'] ?? ''}',
    name: '${j['name'] ?? ''}',
    model: '${j['model'] ?? ''}',
    providerId: '${j['providerId'] ?? ''}',
    thinking: j['thinking'] == true,
    thinkingLevel: '${j['thinkingLevel'] ?? 'medium'}',
    multimodal: j['multimodal'] == true,
    // 缺键（老数据）回退默认三档；显式空数组（用户清空）保留
    thinkingLevels:
        ((j['thinkingLevels'] as List?)?.map((e) => '$e').toList()) ??
        const ['low', 'medium', 'high'],
    maxContext: (j['maxContext'] as num?)?.toInt(),
    maxOutput: (j['maxOutput'] as num?)?.toInt(),
    // 缺键（老数据）给默认 5 / 10
    retries: (j['retries'] as num?)?.toInt() ?? 5,
    ratePerMin: (j['ratePerMin'] as num?)?.toInt() ?? 10,
  );
}

/// 全局设置（主题 / AI 多提供商多模型 / 数据目录 / 悬浮窗）
class SettingsService extends ChangeNotifier {
  static final SettingsService I = SettingsService._();

  SettingsService._();

  late SharedPreferences _sp;

  // ---- 外观 ----
  ThemeMode themeMode = ThemeMode.system;
  int accentValue = 0xFF4F6BFF;
  bool useCustomColor = false;
  AppStyle styleMode = AppStyle.material;

  /// 跟读高亮：播放时逐句染色（读完的句子/当前句变色）
  bool followHighlight = true;
  UiLayoutMode layoutMode = UiLayoutMode.auto; // 安卓平板/手机布局

  // ---- AI（多提供商 / 多模型）----
  List<AiProvider> providers = [];
  List<AiModel> models = [];
  String currentModelId = '';

  // ---- 提取通道开关（Root / Shizuku 可随时取消或重新启用）----
  bool useRoot = true;
  bool useShizuku = true;

  /// 启动时自动检测更新（查官网版本号，可关）
  bool autoCheckUpdate = true;

  void setChannel({bool? root, bool? shizuku}) {
    if (root != null) {
      useRoot = root;
      _sp.setBool('useRoot', root);
    }
    if (shizuku != null) {
      useShizuku = shizuku;
      _sp.setBool('useShizuku', shizuku);
    }
    notifyListeners();
  }

  // ---- AI 调用策略 ----
  int aiRetryCount = 3; // 失败自动重试次数（重试用尽才切换下一个模型）
  int aiRatePerMin = 0; // 速率限制：次/分钟，0=不限（Agnes 免费建议 10）

  // ---- 数据根目录 ----
  String windowsRoot = '';
  String androidRoot =
      '/storage/emulated/0/Android/data/com.ets100.secondary/files/Download/ETS_secondary/resource';
  List<String> extraRoots = [];

  bool get aiReady {
    final m = currentModel;
    if (m == null) return false;
    final pr = providerOf(m);
    return pr != null &&
        pr.apiKey.trim().isNotEmpty &&
        m.model.trim().isNotEmpty;
  }

  /// 当前（首选）模型：未选择则为 null —— 默认不使用任何模型
  AiModel? get currentModel {
    if (currentModelId.isEmpty) return null;
    for (final m in models) {
      if (m.id == currentModelId) return m;
    }
    return null;
  }

  /// 故障切换链：当前模型优先，其余按用户排列顺序兜底
  List<AiModel> get failoverChain {
    final ready = models
        .where(
          (m) =>
              m.model.trim().isNotEmpty &&
              (providerOf(m)?.apiKey.trim().isNotEmpty ?? false),
        )
        .toList();
    if (currentModelId.isEmpty) return ready;
    final cur = ready.where((m) => m.id == currentModelId).toList();
    final rest = ready.where((m) => m.id != currentModelId).toList();
    return [...cur, ...rest];
  }

  AiProvider? providerOf(AiModel m) {
    for (final pr in providers) {
      if (pr.id == m.providerId) return pr;
    }
    return null;
  }

  /// Agnes 提供商（按 baseUrl 识别）
  bool isAgnesProvider(String providerId) {
    for (final pr in providers) {
      if (pr.id == providerId) return pr.baseUrl.trim() == kAgnesBaseUrl;
    }
    return false;
  }


  Future<void> load() async {
    _sp = await SharedPreferences.getInstance();
    themeMode = ThemeMode.values[_sp.getInt('themeMode') ?? 0];
    accentValue = _sp.getInt('accent') ?? accentValue;
    useCustomColor = _sp.getBool('useCustomColor') ?? false;
    styleMode = AppStyle.values[_sp.getInt('styleMode') ?? 0];
    followHighlight = _sp.getBool('followHighlight') ?? true;
    layoutMode = UiLayoutMode.values[_sp.getInt('layoutMode') ?? 0];
    windowsRoot = _sp.getString('windowsRoot') ?? '';
    androidRoot = _sp.getString('androidRoot') ?? androidRoot;
    extraRoots = _sp.getStringList('extraRoots') ?? [];
    showDemoData = _sp.getBool('showDemoData') ?? true;
    grade = _sp.getString('grade') ?? '';
    region = _sp.getString('region') ?? '';
    useRoot = _sp.getBool('useRoot') ?? true;
    useShizuku = _sp.getBool('useShizuku') ?? true;
    autoCheckUpdate = _sp.getBool('autoCheckUpdate') ?? true;
    aiRetryCount = _sp.getInt('aiRetryCount') ?? 3;
    aiRatePerMin = _sp.getInt('aiRatePerMin') ?? 0;

    providers = ((_sp.getString('providers') ?? '').isNotEmpty)
        ? ((jsonDecode(_sp.getString('providers')!) as List)
              .whereType<Map>()
              .map((e) => AiProvider.fromJson(e.cast<String, dynamic>()))
              .toList())
        : [];
    models = ((_sp.getString('models') ?? '').isNotEmpty)
        ? ((jsonDecode(_sp.getString('models')!) as List)
              .whereType<Map>()
              .map((e) => AiModel.fromJson(e.cast<String, dynamic>()))
              .toList())
        : [];
    currentModelId = _sp.getString('currentModelId') ?? '';

    // API Key 从系统加密存储读取（Windows DPAPI / Android Keystore）
    await _loadKeysSecure();
    _migrateLegacyAi();
    _ensureDefaults();
  }

  /// 旧版单一 AI 配置迁移
  void _migrateLegacyAi() {
    final legacyKey = _sp.getString('aiApiKey') ?? '';
    final legacyUrl = _sp.getString('aiBaseUrl') ?? '';
    final legacyModel = _sp.getString('aiModel') ?? '';
    if (providers.isEmpty && legacyKey.isNotEmpty) {
      final pr = AiProvider(
        id: 'p${DateTime.now().millisecondsSinceEpoch}',
        name: '默认提供商',
        baseUrl: legacyUrl,
        apiKey: legacyKey,
      );
      providers = [pr];
      models = [
        AiModel(
          id: 'm${DateTime.now().millisecondsSinceEpoch}',
          name: legacyModel,
          model: legacyModel,
          providerId: pr.id,
        ),
      ];
      currentModelId = models.first.id;
      _saveAi();
    }
  }

  void _ensureDefaults() {
    // 默认只添加 Agnes提供商；其他提供商仅在“添加提供商”预设里出现
    // 旧名称统一迁移
    for (var i = 0; i < providers.length; i++) {
      if (providers[i].name == 'Agnes 中国站' ||
          providers[i].name == 'Agnes（免费额度）' ||
          providers[i].name == 'Agnes') {
        providers[i].name = kAgnesPresetName;
      }
    }
    final seeded = _sp.getBool('presetsSeeded') ?? false;
    if (!seeded) {
      final hasAgnes = providers.any((e) => e.baseUrl == kAgnesBaseUrl);
      if (!hasAgnes) {
        providers = [
          AiProvider(
            id: 'preset_agnes',
            name: kAgnesPresetName,
            baseUrl: kAgnesBaseUrl,
            apiKey: '',
          ),
          ...providers,
        ];
      }
      _sp.setBool('presetsSeeded', true);
    }
    if (providers.isEmpty) {
      providers = [
        AiProvider(
          id: 'preset_agnes',
          name: kAgnesPresetName,
          baseUrl: kAgnesBaseUrl,
          apiKey: '',
        ),
      ];
    }
    // 首次使用：默认模型 agnes-3.0-flash（填 Key 后即可用）
    final agnesSeeded = _sp.getBool('agnesModelSeeded') ?? false;
    if (!agnesSeeded) {
      final agnes = providers.firstWhere(
        (e) => e.baseUrl == kAgnesBaseUrl,
        orElse: () => providers.first,
      );
      if (!models.any((m) => m.model.trim() == 'agnes-3.0-flash')) {
        models = [
          AiModel(
            id: 'agnes-3-0-flash',
            name: 'Agnes 3.0 Flash',
            model: 'agnes-3.0-flash',
            providerId: agnes.id,
            // Agnes 出厂档位就是关/开（不注入 effort）；想要低/中/高可在编辑模型里自行添加
            thinkingLevel: 'on',
            thinkingLevels: const ['on'],
            multimodal: true,
          ),
          ...models,
        ];
      }
      if (currentModelId.isEmpty) {
        currentModelId = 'agnes-3-0-flash';
      }
      _sp.setBool('agnesModelSeeded', true);
    }
    // 思考档位兜底：老数据/历史 bug 产生的空列表补默认三档；
    // 当前档位不在启用列表里时归位（清理残留的旧档位）
    for (var i = 0; i < models.length; i++) {
      if (models[i].thinkingLevels.isEmpty) {
        models[i].thinkingLevels = ['low', 'medium', 'high'];
      }
      if (models[i].thinking &&
          !models[i].thinkingLevels.contains(models[i].thinkingLevel)) {
        models[i].thinkingLevel = models[i].thinkingLevels.first;
      }
    }
    // agnes-3.0-flash 上下文 512000 / 输出 65536（用户未手动设定时补默认值）
    for (final m in models) {
      if (m.model.trim() == 'agnes-3.0-flash') {
        m.maxContext ??= 512000;
        m.maxOutput ??= 65536;
      }
    }
    if (!models.any((m) => m.id == currentModelId)) {
      currentModelId = '';
    }
    _saveAi();
  }

  void _saveAi() {
    // 提供商列表明文存储（不含 Key）；Key 走系统加密存储
    _sp.setString(
      'providers',
      jsonEncode(providers.map((e) => e.toJson()..['apiKey'] = '').toList()),
    );
    _sp.setString('models', jsonEncode(models.map((e) => e.toJson()).toList()));
    _sp.setString('currentModelId', currentModelId);
    _saveKeysSecure();
    notifyListeners();
  }

  // ---- API Key 加密存储（flutter_secure_storage）----
  // Windows: DPAPI（绑定当前用户）  Android: Keystore + AES
  final _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> _loadKeysSecure() async {
    try {
      final raw = await _secure.read(key: 'ai_keys');
      if (raw == null || raw.isEmpty) return;
      final map = (jsonDecode(raw) as Map).cast<String, dynamic>();
      for (final pr in providers) {
        final k = '${map[pr.id] ?? ''}';
        if (k.isNotEmpty) pr.apiKey = k;
      }
    } catch (_) {}
  }

  Future<void> _saveKeysSecure() async {
    try {
      final map = {for (final pr in providers) pr.id: pr.apiKey};
      await _secure.write(key: 'ai_keys', value: jsonEncode(map));
    } catch (_) {}
  }

  // ---- 外观操作 ----
  void setThemeMode(ThemeMode m) {
    themeMode = m;
    _sp.setInt('themeMode', m.index);
    notifyListeners();
  }

  void setAccent(int v, {bool custom = true}) {
    accentValue = v;
    useCustomColor = custom;
    _sp.setInt('accent', v);
    _sp.setBool('useCustomColor', custom);
    notifyListeners();
  }

  void setFollowHighlight(bool v) {
    followHighlight = v;
    _sp.setBool('followHighlight', v);
  }

  void setAutoCheckUpdate(bool v) {
    autoCheckUpdate = v;
    _sp.setBool('autoCheckUpdate', v);
    notifyListeners();
  }

  void setStyleMode(AppStyle s) {
    styleMode = s;
    _sp.setInt('styleMode', s.index);
    notifyListeners();
  }

  void setLayoutMode(UiLayoutMode m) {
    layoutMode = m;
    _sp.setInt('layoutMode', m.index);
    notifyListeners();
  }

  // ---- AI 操作 ----
  void addProvider(AiProvider pr) {
    providers = [...providers, pr];
    _saveAi();
  }

  void updateProvider(AiProvider pr) {
    providers = [
      for (final e in providers)
        if (e.id == pr.id) pr else e,
    ];
    _saveAi();
  }

  void removeProvider(String id) {
    providers = providers.where((e) => e.id != id).toList();
    models = models.where((e) => e.providerId != id).toList();
    _ensureDefaults();
  }

  void addModel(AiModel m) {
    models = [...models, m];
    currentModelId = m.id;
    _saveAi();
  }

  void updateModel(AiModel m) {
    models = [
      for (final e in models)
        if (e.id == m.id) m else e,
    ];
    _saveAi();
  }

  void removeModel(String id) {
    models = models.where((e) => e.id != id).toList();
    _ensureDefaults();
  }

  /// 思考档位菜单项：关 + 已启用档位（按配置顺序）+ 其余标准档位。
  /// 后面那截保证任何档位都能直接选到，不因为没勾选就"调不了"。
  List<String> thinkingMenuLevels(AiModel? m) {
    final enabled = m?.thinkingLevels ?? const <String>[];
    return [
      'off',
      ...enabled,
      ...kThinkingLevelOrder.where((lv) => !enabled.contains(lv)),
    ];
  }

  /// 选档位：'off' = 关闭思考；其他档位若没在启用列表里就顺手加进去
  /// （不加的话启动兜底会把「不在列表里的档位」顶回第一档，选了等于白选）
  void setThinkingOption(AiModel m, String level) {
    if (level == 'off') {
      updateModel(m.copyWith(thinking: false));
      return;
    }
    updateModel(
      m.copyWith(
        thinking: true,
        thinkingLevel: level,
        thinkingLevels: m.thinkingLevels.contains(level)
            ? m.thinkingLevels
            : [...m.thinkingLevels, level],
      ),
    );
  }

  /// 模型调用优先级：上移/下移（failover 顺序）
  void moveModel(String id, int delta) {
    final i = models.indexWhere((e) => e.id == id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= models.length) return;
    final m = models.removeAt(i);
    models.insert(j, m);
    _saveAi();
  }

  void setAiPolicy({int? retryCount, int? ratePerMin}) {
    aiRetryCount = retryCount ?? aiRetryCount;
    aiRatePerMin = ratePerMin ?? aiRatePerMin;
    _sp.setInt('aiRetryCount', aiRetryCount);
    _sp.setInt('aiRatePerMin', aiRatePerMin);
    notifyListeners();
  }

  // ---- 修改栏：成绩 / 完成时间 规则（拦截引擎现读现用）----
  bool get captureScoreOn => _sp.getBool('captureScoreOn') ?? false;
  String get captureScore => _sp.getString('captureScore') ?? '';

  /// 高级模式：按题型精确设分（category → 每小题得分）
  bool get captureAdvancedOn => _sp.getBool('captureAdvancedOn') ?? false;

  Map<String, double> get captureCategoryScoreMap {
    final raw = _sp.getString('captureCategoryScores');
    if (raw == null || raw.isEmpty) return const {};
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return const {};
      return {
        for (final e in m.entries)
          if (double.tryParse('${e.value}') != null)
            '${e.key}': double.parse('${e.value}'),
      };
    } catch (_) {
      return const {};
    }
  }

  bool get captureTimeOn => _sp.getBool('captureTimeOn') ?? false;

  /// 完成时刻提前量（秒）：-1 = 全空不修改；>=0 主动提前该秒数（0 = 按提交时刻上传）
  int get captureTimeSec => _sp.getInt('captureTimeSec') ?? -1;

  /// 引擎监听端口
  int get capturePort => _sp.getInt('capturePort') ?? 8888;

  void setCaptureScore({bool? on, String? value}) {
    if (on != null) _sp.setBool('captureScoreOn', on);
    if (value != null) _sp.setString('captureScore', value);
    notifyListeners();
  }

  void setCaptureAdvanced({bool? on, Map<String, double>? scores}) {
    if (on != null) _sp.setBool('captureAdvancedOn', on);
    if (scores != null) {
      _sp.setString(
        'captureCategoryScores',
        scores.isEmpty ? '' : jsonEncode(scores),
      );
    }
    notifyListeners();
  }

  void setCaptureTime({bool? on, int? sec}) {
    if (on != null) _sp.setBool('captureTimeOn', on);
    if (sec != null) _sp.setInt('captureTimeSec', sec);
    notifyListeners();
  }

  void setCapturePort(int port) {
    _sp.setInt('capturePort', port);
    notifyListeners();
  }

  // ---- 考试信息（格式匹配：初中/高中、地区）----
  String grade = ''; // 初一~高三
  String region = ''; // 如 广东东莞

  void setExamInfo({String? grade, String? region}) {
    if (grade != null) {
      this.grade = grade;
      _sp.setString('grade', grade);
    }
    if (region != null) {
      this.region = region;
      _sp.setString('region', region);
    }
    notifyListeners();
  }

  bool get isJunior => grade == '初一' || grade == '初二' || grade == '初三';

  // ---- 作业管理：已完成 / 已删除（按目录 key）----
  Set<String> get completedDirs =>
      (_sp.getStringList('completedDirs') ?? []).toSet();
  Set<String> get deletedDirs =>
      (_sp.getStringList('deletedDirs') ?? []).toSet();

  void setCompleted(Iterable<String> keys, bool completed) {
    final set = completedDirs;
    for (final k in keys) {
      if (completed) {
        set.add(k);
      } else {
        set.remove(k);
      }
    }
    _sp.setStringList('completedDirs', set.toList());
    notifyListeners();
  }

  /// 物理删除后清理这些目录的完成/删除记录，避免幽灵键
  void forgetDirs(Iterable<String> keys) {
    final set = keys.toSet();
    final done = completedDirs.where((e) => !set.contains(e)).toList();
    final del = deletedDirs.where((e) => !set.contains(e)).toList();
    _sp.setStringList('completedDirs', done);
    _sp.setStringList('deletedDirs', del);
    notifyListeners();
  }

  void setDeleted(Iterable<String> keys) {
    final set = deletedDirs;
    set.addAll(keys);
    _sp.setStringList('deletedDirs', set.toList());
    notifyListeners();
  }

  void restoreDeleted() {
    _sp.remove('deletedDirs');
    notifyListeners();
  }

  // ---- 新手教程 / 演示数据 ----
  bool get onboardDone => _sp.getBool('onboardDone') ?? false;

  void finishOnboarding() {
    _sp.setBool('onboardDone', true);
    notifyListeners();
  }

  bool showDemoData = true;

  bool get tourRequested => _sp.getBool('tourRequested') ?? false;

  void requestTour({bool value = true}) {
    _sp.setBool('tourRequested', value);
    notifyListeners();
  }

  void setShowDemoData(bool v) {
    showDemoData = v;
    _sp.setBool('showDemoData', v);
    notifyListeners();
  }

  void setCurrentModel(String id) {
    currentModelId = id;
    _sp.setString('currentModelId', id);
    notifyListeners();
  }

  // ---- 数据目录 ----
  void addExtraRoot(String dir) {
    if (dir.isEmpty || extraRoots.contains(dir)) return;
    extraRoots = [...extraRoots, dir];
    _sp.setStringList('extraRoots', extraRoots);
    notifyListeners();
  }

  void removeExtraRoot(String dir) {
    extraRoots = extraRoots.where((e) => e != dir).toList();
    _sp.setStringList('extraRoots', extraRoots);
    notifyListeners();
  }

  /// 覆盖 Android 扫描根（提取副本后指向应用私有目录）
  void setAndroidRoot(String dir) {
    androidRoot = dir;
    _sp.setString('androidRoot', dir);
    notifyListeners();
  }

  void resetAndroidRoot() {
    androidRoot = platformDefaultRoot;
    _sp.setString('androidRoot', androidRoot);
    notifyListeners();
  }

  /// 平台默认数据根
  static String get platformDefaultRoot {
    if (Platform.isWindows) {
      final appdata =
          Platform.environment['APPDATA'] ?? r'C:\Users\Admin\AppData\Roaming';
      return p.join(appdata, 'ETS');
    }
    if (Platform.isAndroid) {
      return '/storage/emulated/0/Android/data/com.ets100.secondary/files/Download/ETS_secondary/resource';
    }
    return '.';
  }

  /// Android 申请所有文件访问权限（读取 Android/data 下 E听说 数据）
  static Future<bool> requestAndroidStorage() async {
    if (!Platform.isAndroid) return true;
    if (await Permission.manageExternalStorage.isGranted) return true;
    final s = await Permission.manageExternalStorage.request();
    return s.isGranted;
  }

  /// Android 申请麦克风权限（模拟考场录音）
  static Future<bool> requestMic() async {
    if (!Platform.isAndroid) return true;
    if (await Permission.microphone.isGranted) return true;
    final s = await Permission.microphone.request();
    return s.isGranted;
  }

  /// 当前生效的所有数据根
  List<String> get activeRoots {
    final list = <String>[];
    if (Platform.isWindows) {
      list.add(windowsRoot.isNotEmpty ? windowsRoot : platformDefaultRoot);
    } else if (Platform.isAndroid) {
      list.add(androidRoot);
    }
    list.addAll(extraRoots);
    // 新手教程期间展示内置演示作业（路径由 DemoService.prepare 回填）
    if (!onboardDone && showDemoData && demoRootPath.isNotEmpty) {
      list.add(demoRootPath);
    }
    return list.where((e) => e.isNotEmpty).toList();
  }

  /// 演示作业数据根（main 启动时由 DemoService 回填）
  String demoRootPath = '';
}
