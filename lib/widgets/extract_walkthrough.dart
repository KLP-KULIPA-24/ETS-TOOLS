import 'package:flutter/material.dart';

import '../services/extract_service.dart';

/// 选择工作授权模式：四通道（SHIZUKU / ROOT / DIRECT_READ / SAF）
/// 参照 ETSToolbox 的模式选择形态：单选卡 + 徽章 + 说明 + 实时状态 + 操作
class ExtractWalkthrough extends StatefulWidget {
  /// 提取完成回调（外部负责关闭面板/刷新列表）
  final Future<void> Function(String message) onExtract;

  const ExtractWalkthrough({super.key, required this.onExtract});

  @override
  State<ExtractWalkthrough> createState() => _ExtractWalkthroughState();
}

class _ExtractWalkthroughState extends State<ExtractWalkthrough> {
  ExtractMode? _selected;
  Map<ExtractMode, bool>? _ready;
  Map<ExtractMode, String>? _stateText;
  bool _busy = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _probe();
  }

  Future<void> _probe() async {
    final pr = await ExtractService.probeAll();
    if (!mounted) return;
    final ready = <ExtractMode, bool>{
      ExtractMode.shizuku: pr?.shizuku == true,
      ExtractMode.root: pr?.root == true,
      ExtractMode.directRead: pr?.directRead == true,
      ExtractMode.saf: pr?.saf == true,
    };
    final stateText = <ExtractMode, String>{
      ExtractMode.shizuku: switch (pr?.shizukuInstalled) {
        true => pr?.shizuku == true ? '已授权，可直接提取' : '已安装，需点击右侧授权',
        _ => '未安装：先装 Shizuku 并用无线调试启动',
      },
      ExtractMode.root: pr?.root == true
          ? '已检测到 Root，可直接提取'
          : '未检测到 Root（模拟器可在设置里开启）',
      ExtractMode.directRead: pr?.directRead == true
          ? '直接直读已就绪'
          : '该设备不支持直读（FUSE 已限制）',
      ExtractMode.saf: pr?.saf == true ? '已授权数据目录' : '尚未授权：点击右侧选择 E听说 数据目录',
    };
    setState(() {
      _ready = ready;
      _stateText = stateText;
      // 默认选中第一个就绪的通道（按推荐顺序）
      if (_selected == null) {
        final hits = ready.entries
            .where((e) => e.value)
            .map((e) => e.key)
            .toList();
        _selected = hits.isEmpty ? null : hits.first;
      }
    });
  }

  Future<void> _requestShizuku() async {
    setState(() => _busy = true);
    final svc = await ExtractService.requestShizuku();
    await Future.delayed(const Duration(seconds: 2));
    await _probe();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = svc == 'ok' ? 'Shizuku 已授权' : 'Shizuku 未就绪（$svc）';
    });
  }

  Future<void> _requestSaf() async {
    setState(() => _busy = true);
    final r = await ExtractService.requestSaf();
    await _probe();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = r == 'ok' ? 'SAF 目录已授权' : '未完成 SAF 授权（$r）';
    });
  }

  Future<void> _extract() async {
    final mode = _selected;
    if (mode == null || _busy) return;
    setState(() {
      _busy = true;
      _status = '正在用 ${mode.label} 提取…';
    });
    final (ok, msg) = await ExtractService.extract(mode);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = msg;
    });
    if (ok) await widget.onExtract(msg);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ready = _ready;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('选择工作授权模式', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            '四条通道任选其一，把 E听说 私有数据拷到本应用即可。'
            '勾选状态的通道可直接提取；没有就绪的先按卡片右侧按钮准备。',
            style: TextStyle(fontSize: 12, color: cs.outline, height: 1.5),
          ),
          const SizedBox(height: 12),
          if (ready == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...[
            for (final mode in ExtractMode.values) ...[
              _ModeCard(
                mode: mode,
                selected: _selected == mode,
                ready: ready[mode] == true,
                stateText: _stateText?[mode] ?? '',
                busy: _busy,
                onSelect: () => setState(() => _selected = mode),
                onPrepare: switch (mode) {
                  ExtractMode.shizuku => _requestShizuku,
                  ExtractMode.saf => _requestSaf,
                  _ => null,
                },
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_selected == null || _busy) ? null : _extract,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_alt_rounded),
                label: Text(
                  _busy ? '提取中…' : '用 ${_selected?.label ?? '—'} 开始提取',
                ),
              ),
            ),
          ],
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _status,
              style: TextStyle(
                fontSize: 12,
                color: _status.contains('成功') ? Colors.green : cs.outline,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 单张模式卡：单选 + 名称 + 徽章 + 说明 + 状态 + 准备操作
class _ModeCard extends StatelessWidget {
  final ExtractMode mode;
  final bool selected;
  final bool ready;
  final String stateText;
  final bool busy;
  final VoidCallback onSelect;
  final VoidCallback? onPrepare;

  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.ready,
    required this.stateText,
    required this.busy,
    required this.onSelect,
    this.onPrepare,
  });

  String get _badge => switch (mode) {
    ExtractMode.shizuku => 'Recommended',
    ExtractMode.root => 'Highest Perm',
    ExtractMode.directRead => 'No Root',
    ExtractMode.saf => 'System Picker',
  };

  IconData get _icon => switch (mode) {
    ExtractMode.shizuku => Icons.api_rounded,
    ExtractMode.root => Icons.verified_user_rounded,
    ExtractMode.directRead => Icons.folder_open_rounded,
    ExtractMode.saf => Icons.folder_shared_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onSelect,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? cs.primaryContainer.withValues(alpha: 0.45)
              : cs.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? cs.primary
                : cs.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 20,
                  color: selected ? cs.primary : cs.outline,
                ),
                const SizedBox(width: 8),
                Icon(_icon, size: 18, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    mode.label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  _badge,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: mode == ExtractMode.shizuku
                        ? cs.primary
                        : cs.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Text(
                mode.desc,
                style: TextStyle(fontSize: 12, color: cs.outline, height: 1.45),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Row(
                children: [
                  Icon(
                    ready
                        ? Icons.check_circle_rounded
                        : Icons.info_outline_rounded,
                    size: 15,
                    color: ready ? Colors.green : cs.outline,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      stateText,
                      style: TextStyle(fontSize: 12, color: cs.outline),
                    ),
                  ),
                  // 授权按钮常驻：授权状态可能失效（选错层级 / 系统回收授权），
                  // 已就绪时显示「重新授权」允许重选
                  if (onPrepare != null)
                    TextButton(
                      onPressed: busy ? null : onPrepare,
                      child: Text(
                        !ready
                            ? (mode == ExtractMode.shizuku
                                  ? '授权 Shizuku'
                                  : '授权目录')
                            : '重新授权',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
