import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/achievements.dart';
import '../../widgets/glass.dart';
import '../../widgets/style.dart';

/// 成就页：已解锁显示详情，未解锁灰色剪影，隐藏项解锁前不出现
class AchievementsPage extends StatelessWidget {
  const AchievementsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final wide = MediaQuery.of(context).size.width >= 700;
    // 隐藏项：解锁前不展示
    final list = Achievements.all
        .where((a) => !a.hidden || Achievements.isUnlocked(a.id))
        .toList();
    final unlockedCount = list
        .where((a) => Achievements.isUnlocked(a.id))
        .length;

    return GlassWall(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (wide)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Text(
                '成就',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, wide ? 4 : 16, 16, 0),
            child: Text(
              '已解锁 $unlockedCount / ${list.length}',
              style: TextStyle(fontSize: 13, color: cs.outline),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final a = list[i];
                final got = Achievements.isUnlocked(a.id);
                final at = Achievements.unlockedAt(a.id);
                return AppCard(
                  radius: 18,
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: got
                              ? cs.primary.withValues(alpha: 0.14)
                              : cs.outlineVariant.withValues(alpha: 0.35),
                        ),
                        child: Icon(
                          got ? a.icon : Icons.lock_rounded,
                          size: 21,
                          color: got ? cs.primary : cs.outline,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              got ? a.name : '？？？',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: got ? null : cs.outline,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              got ? a.desc : '未解锁',
                              style: TextStyle(fontSize: 12, color: cs.outline),
                            ),
                            if (got && a.target != null) ...[
                              const SizedBox(height: 3),
                              Text(
                                '进度 ${Achievements.counter(a.id)}/${a.target}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.outline,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (got && at != null)
                        Text(
                          DateFormat('yyyy-MM-dd')
                              .format(DateTime.fromMillisecondsSinceEpoch(at)),
                          style: TextStyle(fontSize: 12, color: cs.outline),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
