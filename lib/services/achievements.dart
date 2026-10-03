import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 成就定义
class Achievement {
  final String id;
  final String name;
  final String desc;
  final IconData icon;
  final bool hidden; // 标记：解锁前不在列表显示（不提示存在）
  final String? target; // 累计类目标（如 '10'）

  const Achievement({
    required this.id,
    required this.name,
    required this.desc,
    required this.icon,
    this.hidden = false,
    this.target,
  });
}

/// 本地成就服务：解锁记录（prefs）+ 全局提示
class Achievements {
  Achievements._();
  static final Achievements I = Achievements._();

  static final navigatorKey = GlobalKey<NavigatorState>();

  /// 成就清单（隐藏项名称/描述用 Base64，源码零明文）
  static final List<Achievement> all = [
    Achievement(
      id: 'start',
      name: '启程',
      desc: '首次扫描到 E听说 作业数据',
      icon: Icons.explore_rounded,
    ),
    Achievement(
      id: 'first_chat',
      name: '初试锋芒',
      desc: '完成第一次 AI 对话',
      icon: Icons.forum_rounded,
    ),
    Achievement(
      id: 'chat_10',
      name: '话题收集者',
      desc: '累计对话 10 次',
      icon: Icons.chat_bubble_rounded,
      target: '10',
    ),
    Achievement(
      id: 'batch_title',
      name: '批量达人',
      desc: '首次一键生成缺失标题',
      icon: Icons.auto_awesome_rounded,
    ),
    Achievement(
      id: 'collector',
      name: '收纳癖',
      desc: '累计完成并收纳 3 个作业',
      icon: Icons.inventory_2_rounded,
      target: '3',
    ),
    Achievement(
      id: 'floating',
      name: '悬浮窗达人',
      desc: '开启过悬浮窗/悬浮模式',
      icon: Icons.picture_in_picture_alt_rounded,
    ),
    Achievement(
      id: 'exam',
      name: '考场体验者',
      desc: '进入过模拟考场',
      icon: Icons.assignment_turned_in_rounded,
    ),
    Achievement(
      id: 'cleaner',
      name: '整理控',
      desc: '永久删除过 1 个作业文件夹',
      icon: Icons.cleaning_services_rounded,
    ),
    Achievement(
      id: 'night_owl',
      name: '深夜旅人',
      desc: '在凌晨 0-5 点打开应用',
      icon: Icons.nightlight_round,
    ),
    // 隐藏项：名称/描述 Base64（源码零明文）
    Achievement(
      id: 'a7f3e2',
      name: utf8.decode(base64Decode('5b2p6JuL')),
      desc: utf8.decode(
        base64Decode(
          '6Kem5Y+R5p+Q5Liq6ZqQ6JeP5p2h5Lu25ZCO6Kej6ZSB55qE5oiQ5bCx',
        ),
      ),
      icon: Icons.auto_awesome_rounded,
      hidden: true,
    ),
  ];

  static Achievement byId(String id) =>
      all.firstWhere((a) => a.id == id, orElse: () => all.first);

  // ---- 存储 ----
  static SharedPreferences? _sp;
  static final Map<String, int> _unlocked = {};
  static final Map<String, int> _counters = {};

  static Future<void> init() async {
    _sp ??= await SharedPreferences.getInstance();
    final raw = _sp!.getString('achievements') ?? '{}';
    try {
      _unlocked.addAll(
        (jsonDecode(raw) as Map).map(
          (k, v) => MapEntry('$k', (v as num).toInt()),
        ),
      );
    } catch (_) {}
    final craw = _sp!.getString('achievementCounters') ?? '{}';
    try {
      _counters.addAll(
        (jsonDecode(craw) as Map).map(
          (k, v) => MapEntry('$k', (v as num).toInt()),
        ),
      );
    } catch (_) {}
  }

  static bool isUnlocked(String id) => _unlocked.containsKey(id);
  static int? unlockedAt(String id) => _unlocked[id];
  static int counter(String id) => _counters[id] ?? 0;

  static void _save() {
    _sp?.setString('achievements', jsonEncode(_unlocked));
    _sp?.setString('achievementCounters', jsonEncode(_counters));
  }

  /// 累计计数并检查类成就（如对话 10 次）；[check] 达成的即时解锁
  static void bump(String id, {int delta = 1}) {
    if (!isUnlocked(id)) {
      _counters[id] = counter(id) + delta;
      _save();
      final a = all.firstWhere((x) => x.id == id, orElse: () => all.first);
      final target = int.tryParse(a.target ?? '');
      if (target != null && _counters[id]! >= target) {
        unlock(id);
      }
    }
  }

  /// 解锁（已解锁则忽略）
  static void unlock(String id) {
    if (isUnlocked(id)) return;
    _unlocked[id] = DateTime.now().millisecondsSinceEpoch;
    _save();
    final a = all.firstWhere((x) => x.id == id, orElse: () => all.first);
    _toast('成就解锁 ✨ ${a.name}', a.desc);
  }

  static void _toast(String title, String desc) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(desc, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      );
  }
}
