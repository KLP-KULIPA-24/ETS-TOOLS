import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/ets_models.dart';
import 'settings_service.dart';
import 'achievements.dart';

/// ETS 数据扫描服务：递归扫描所有数据根，发现 content_* 与 paper.Jason
class EtsDataService extends ChangeNotifier {
  static final EtsDataService I = EtsDataService._();

  EtsDataService._();

  final List<HomeworkEntry> entries = [];
  bool scanning = false;
  String lastError = '';

  /// 各根目录的扫描状态
  final Map<String, String> rootStatus = {};

  /// [silent] = 静默刷新：扫描期间**保留旧列表不通知**，扫完整体替换。
  /// 原实现一上来就 `entries.clear(); notifyListeners();`，作业列表会先整片
  /// 消失再重新出现——打开作业页的自动刷新正好走这条路径，闪一下很扎眼。
  Future<void> rescan({bool silent = false}) async {
    if (scanning) return;
    scanning = true;
    lastError = '';
    final previous = silent
        ? List<HomeworkEntry>.of(entries)
        : <HomeworkEntry>[];
    if (!silent) {
      entries.clear();
      notifyListeners();
    }
    final collected = <HomeworkEntry>[];

    final aiTitles = await loadAiTitles();
    final roots = SettingsService.I.activeRoots;
    for (final root in roots) {
      try {
        final dir = Directory(root);
        if (!dir.existsSync()) {
          rootStatus[root] = '目录不存在';
          continue;
        }
        final found = await compute(_scanRoot, root);
        // 应用 AI 生成的标题（titleSource=ai）
        for (var i = 0; i < found.length; i++) {
          final e = found[i];
          final key = e.content?.stid ?? e.paper?.tzid ?? '';
          final t = aiTitles[key];
          if (t != null && t.isNotEmpty) {
            found[i] = HomeworkEntry(
              uid: e.uid,
              dir: e.dir,
              mtime: e.mtime,
              content: e.content,
              paper: e.paper,
              title: t,
              titleSource: TitleSource.ai,
            );
          }
        }
        (silent ? collected : entries).addAll(found);
        final folderCount = computeGroups(found).length;
        rootStatus[root] = '已扫描 $folderCount 个文件夹';
      } catch (e) {
        rootStatus[root] = '扫描失败: $e';
        lastError = '$e';
      }
    }
    final target = silent ? collected : entries;
    target.sort((a, b) => b.mtime.compareTo(a.mtime));
    // 多根目录可能重叠，按目录路径去重
    final seen = <String>{};
    target.retainWhere((e) => seen.add(e.dir));
    if (silent) {
      // 整体替换：中间过程列表一直显示旧内容，不会闪。
      // 一份都没扫到时宁可留着旧数据，也别把列表清空。
      entries
        ..clear()
        ..addAll(target.isEmpty ? previous : target);
    }
    scanning = false;
    if (entries.isNotEmpty) {
      Achievements.unlock('start');
    }
    notifyListeners();
  }

  /// 在 isolate 中执行目录扫描
  static List<HomeworkEntry> _scanRoot(String root) {
    final out = <HomeworkEntry>[];
    final directors = <HomeworkEntry>[];
    final rootDir = Directory(root);
    // 广度优先，深度限制 6
    final queue = <Directory>[rootDir];
    var depth = 0;
    while (queue.isNotEmpty && depth < 6) {
      final next = <Directory>[];
      for (final d in queue) {
        List<FileSystemEntity> children;
        try {
          children = d.listSync(followLinks: false);
        } catch (_) {
          continue;
        }
        for (final c in children) {
          if (c is! Directory) continue;
          final hasContentJson = File(p.join(c.path, 'content.json'))
              .existsSync();
          final hasPaperJason =
              File(p.join(c.path, 'paper.Jason')).existsSync() ||
              File(p.join(c.path, 'paper.jason')).existsSync();
          // Android 新布局：指挥目录（ctrl.json + res.json，无 content.json）
          // 是套题的"流程脚本+分区总表"，不吸收内容目录会被割裂成孤儿
          final hasCtrl = File(p.join(c.path, 'ctrl.json')).existsSync();
          final hasRes = File(p.join(c.path, 'res.json')).existsSync();
          if (hasCtrl && hasRes && !hasContentJson && !hasPaperJason) {
            directors.add(_parseDirectorDir(c));
            continue;
          }
          // Windows 布局：content_* 子目录；Android 布局：任意名（哈希）目录直接是作业
          if (hasPaperJason) {
            // 同时含 content.json + paper.Jason 时优先按套题解析（标题在 paper.Jason）
            final u = _parsePaperDir(c);
            if (u != null) {
              out.add(u);
              continue;
            }
          }
          if (hasContentJson) {
            out.add(_parseContentDir(c));
          }
          next.add(c);
        }
      }
      queue
        ..clear()
        ..addAll(next);
      depth++;
    }
    return _mergeSets(out, directors);
  }

  /// 指挥目录：res.json 的 exam_type_list = 套题分区总表
  /// （名称"模仿朗读/角色扮演/故事复述"、顺序、collector 类型）
  static HomeworkEntry _parseDirectorDir(Directory dir) {
    final res = loadJsonMap(p.join(dir.path, 'res.json'));
    final parts = <SetPart>[];
    for (final t
        in ((res?['exam_type_list'] as List?) ?? const []).whereType<Map>()) {
      parts.add(
        SetPart(
          name: '${t['exam_type_name'] ?? ''}',
          collect: '${t['exam_type_collect'] ?? ''}',
          order: int.tryParse('${t['exam_type_order'] ?? 0}') ?? 0,
        ),
      );
    }
    parts.sort((a, b) => a.order.compareTo(b.order));
    final st = dir.statSync().modified;
    final intro = '${res?['set_intro'] ?? ''}'.trim();
    final title = intro.isNotEmpty
        ? intro
        : (parts.isNotEmpty ? parts.map((x) => x.name).join(' · ') : '套题');
    return HomeworkEntry(
      uid: p.basename(dir.path),
      dir: dir.path,
      mtime: st,
      director: SetDirector(dir: dir.path, parts: parts),
      title: title,
      titleSource: TitleSource.template,
    );
  }

  /// 套题归并：指挥目录按 res.json 声明的 collector 类型吸收同批内容目录，
  /// 一个指挥 + N 个内容目录 = 一份套题；部分顺序 = exam_type_order。
  /// 同批出现多套同类型目录时按修改时间最新配对（罕见场景，保证不静默丢数据）。
  static List<HomeworkEntry> _mergeSets(
    List<HomeworkEntry> entries,
    List<HomeworkEntry> directors,
  ) {
    if (directors.isEmpty) return entries;
    final taken = <String>{};
    final merged = <HomeworkEntry>[];
    for (final d in directors) {
      final members = <HomeworkEntry>[];
      for (final part in d.director!.parts) {
        HomeworkEntry? pick;
        for (final e in entries) {
          if (taken.contains(e.dir)) continue;
          final c = e.content;
          if (c == null || c.structure.key != part.collect) continue;
          if (pick == null || e.mtime.isAfter(pick.mtime)) pick = e;
        }
        if (pick != null) {
          taken.add(pick.dir);
          members.add(
            HomeworkEntry(
              uid: d.uid,
              dir: pick.dir,
              mtime: pick.mtime,
              content: pick.content,
              title: pick.title,
              titleSource: pick.titleSource,
              partName: part.name,
              partOrder: part.order,
            ),
          );
        }
      }
      if (members.isEmpty) {
        merged.add(d); // 指挥无成员：自身占位，防止数据静默丢失
      } else {
        merged.addAll(members);
      }
    }
    merged.addAll(entries.where((e) => !taken.contains(e.dir)));
    return merged;
  }

  /// 分组身份：Windows 布局（content_* 子目录）用父文件夹名；
  /// Android 布局（哈希目录自身即作业文件夹）用自身目录名
  static String _uidFor(String dirPath) {
    final name = p.basename(dirPath);
    if (name.startsWith('content_')) {
      return p.basename(p.dirname(dirPath));
    }
    return name;
  }

  static HomeworkEntry _parseContentDir(Directory dir) {
    final name = p.basename(dir.path);
    final uid = _uidFor(dir.path);
    final raw =
        loadJsonMap(p.join(dir.path, 'content.json')) ??
        loadJsonMap(p.join(dir.path, 'content2.json')) ??
        const {};
    final info = (raw['info'] as Map?)?.cast<String, dynamic>() ?? const {};
    final structure = EtsStructure.fromName('${raw['structure_type']}');
    final unit = ContentUnit(
      dir: dir.path,
      uid: uid,
      folderName: name,
      structure: structure,
      info: info,
      mtime: dir.statSync().modified,
    );

    var title = '';
    var source = TitleSource.fallback;

    // 一级：模板/内置字段提取
    if (unit.topic.isNotEmpty) {
      title = unit.topic;
      source = TitleSource.template;
    } else if (unit.readTitle.isNotEmpty) {
      title = unit.readTitle;
      source = TitleSource.template;
    } else {
      // 二级：自适应（中文标题由列表卡片层组合展示）
      title = unit.adaptiveTitle();
      source = title.startsWith('作业 ')
          ? TitleSource.fallback
          : TitleSource.adaptive;
    }
    return HomeworkEntry(
      uid: uid,
      dir: dir.path,
      mtime: unit.mtime,
      content: unit,
      title: title,
      titleSource: source,
    );
  }

  static HomeworkEntry? _parsePaperDir(Directory dir) {
    final uid = _uidFor(dir.path);
    final jason =
        loadJsonMap(p.join(dir.path, 'paper.Jason')) ??
        loadJsonMap(p.join(dir.path, 'paper.jason'));
    if (jason == null) return null;
    final ctrl = loadJsonMap(p.join(dir.path, 'paper.ctrl')) ?? const {};

    final sections = <PaperSection>[];
    final txlist = (jason['txlist'] as List?) ?? const [];
    for (final tx in txlist.whereType<Map>()) {
      final items = <PaperQuestion>[];
      for (final st in ((tx['stlist'] as List?) ?? const []).whereType<Map>()) {
        items.add(
          PaperQuestion(
            stid: '${st['stid'] ?? ''}',
            score: double.tryParse('${st['st_fs'] ?? 0}') ?? 0,
            title: '${st['title'] ?? ''}',
            audio: '${st['audio'] ?? ''}',
            text: '${st['value'] ?? ''}',
            sentences: ((st['sublist'] as List?) ?? const [])
                .whereType<Map>()
                .map((e) => SentenceSeg.fromJson(e.cast<String, dynamic>()))
                .toList(),
          ),
        );
      }
      sections.add(
        PaperSection(
          name: '${tx['tx_jc'] ?? ''}',
          structure: '${tx['cjq_no'] ?? ''}',
          score: double.tryParse('${tx['tx_fs'] ?? 0}') ?? 0,
          items: items,
        ),
      );
    }
    final st = dir.statSync().modified;
    var title = '${jason['tz_mc'] ?? ''}'.trim();
    var source = TitleSource.template;
    if (title.isEmpty) {
      final comment = '${ctrl['comment'] ?? ''}'.trim();
      if (comment.isNotEmpty) {
        title = comment;
        source = TitleSource.adaptive;
      } else {
        title = '套题 ${jason['tzid'] ?? ''}';
        source = TitleSource.fallback;
      }
    }
    return HomeworkEntry(
      uid: uid,
      dir: dir.path,
      mtime: st,
      paper: PaperUnit(
        dir: dir.path,
        uid: uid,
        tzid: '${jason['tzid'] ?? ''}',
        title: title,
        totalScore: double.tryParse('${jason['tz_fs'] ?? 0}') ?? 0,
        ctrlComment: '${ctrl['comment'] ?? ''}',
        sections: sections,
        mtime: st,
      ),
      title: title,
      titleSource: source,
    );
  }

  /// 把扁平条目收纳成分组：
  /// 1) 按父文件夹（uid）收纳——Windows 布局里 uid 目录名即 set_id，
  ///    一个 uid 就是一份套题（如 Part A/B/C 各一个 content_* 目录）
  /// 2) 保持传入顺序（排序由调用方决定）
  static List<HomeworkGroup> computeGroups(List<HomeworkEntry> entries) {
    final buckets = <String, List<HomeworkEntry>>{};
    for (final e in entries) {
      buckets.putIfAbsent(e.uid, () => []).add(e);
    }
    final groups = <HomeworkGroup>[];
    for (final list in buckets.values) {
      // 组内排序：优先 res.json 的 exam_type_order；
      // Windows 布局没有 res.json 时按题型枚举序（模仿朗读→角色扮演→故事复述）
      final mixedTypes = list.map((e) => e.structure).toSet().length > 1;
      list.sort((a, b) {
        final ao = a.partOrder, bo = b.partOrder;
        if (ao != null && bo != null && ao != bo) return ao.compareTo(bo);
        if (ao != null && bo == null) return -1;
        if (bo != null && ao == null) return 1;
        if (mixedTypes && a.content != null && b.content != null) {
          final d = a.structure.index.compareTo(b.structure.index);
          if (d != 0) return d;
        }
        return b.mtime.compareTo(a.mtime);
      });
      // Part A/B/C 标识：按组内顺序分配。
      // 这套"模仿朗读/角色扮演/故事复述"排版识别切块是广东高中卷特有的
      // （用户明确：地区含广东 + 高一/高二/高三才启用）——
      // 其他地区/学段的数据结构可能不同，不套用这套标签
      if (SettingsService.I.isGuangdongSenior && list.length > 1) {
        for (var i = 0; i < list.length; i++) {
          if (list[i].partLabel == null) {
            list[i] = list[i].copyWith(
              partLabel: 'Part ${String.fromCharCode(65 + i)}',
            );
          }
        }
      }
      final structure = list.first.structure;
      groups.add(
        HomeworkGroup(
          uid: list.first.uid,
          structure: structure,
          title: HomeworkGroup.groupTitleOf(structure, list),
          entries: list,
        ),
      );
    }
    return groups;
  }

  /// AI 批量生成的标题缓存（键为 stid/tzid）
  static Future<String> aiTitlesPath() async {
    final docs = await getApplicationDocumentsDirectory();
    return p.join(docs.path, 'ai_titles.json');
  }

  static Future<Map<String, String>> loadAiTitles() async {
    try {
      final f = File(await aiTitlesPath());
      if (!f.existsSync()) return {};
      final j = jsonDecode(f.readAsStringSync()) as Map;
      return j.map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveAiTitles(Map<String, String> titles) async {
    final f = File(await aiTitlesPath());
    final old = await loadAiTitles();
    old.addAll(titles);
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(jsonEncode(old));
  }

  /// 测试用：扫描单个根目录（公开包装）
  static List<HomeworkEntry> scanRootForTest(String root) => _scanRoot(root);

  /// 解析 ctrl 流程脚本（template ctrl.json 或 paper.ctrl / 子题 ctrl）
  static List<ExamStep> parseCtrlSteps(String path) {
    final raw = loadJsonMap(path);
    if (raw != null) {
      return ((raw['set'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => ExamStep.fromJson(e.cast<String, dynamic>()))
          .toList();
    }
    final list = loadJsonList(path);
    if (list != null) {
      return list
          .whereType<Map>()
          .map((e) => ExamStep.fromJson(e.cast<String, dynamic>()))
          .toList();
    }
    return const [];
  }

  /// 查找 uid 目录下的 template_*/info.json + res.json（完整套题分区信息）
  static List<Map<String, String>> loadTemplateSections(String uidDir) {
    final out = <Map<String, String>>[];
    try {
      for (final e in Directory(uidDir).listSync()) {
        if (e is Directory && p.basename(e.path).startsWith('template_')) {
          final res = loadJsonMap(p.join(e.path, 'res.json'));
          if (res == null) continue;
          for (final t
              in ((res['exam_type_list'] as List?) ?? const [])
                  .whereType<Map>()) {
            out.add({
              'name': '${t['exam_type_name'] ?? ''}',
              'count': '${t['exam_type_count'] ?? ''}',
              'score': '${t['exam_type_score'] ?? ''}',
            });
          }
        }
      }
    } catch (_) {}
    return out;
  }
}
