import 'package:flutter/foundation.dart';

/// 壳层顶栏的可见性开关。
///
/// 手机端壳层（HomeShell）自己画了一条「E听说助手 / 页名」顶栏，页面在它下面。
/// 子界面自带顶栏时（例如 AI 对话的「新对话」），两条顶栏会叠在一起：壳层那条
/// 留在上面，子界面被挤到下方，看起来像"在下方出现"而不是"覆盖当前页"。
/// 子界面把自己登记成沉浸态，壳层就把自己的顶栏整条收掉——子界面的
/// GlassScaffold 会自己补状态栏高度，所以状态栏安全区不会丢。
class ShellChrome {
  ShellChrome._();

  /// 为 true 时，手机端壳层不画顶栏。
  static final ValueNotifier<bool> immersive = ValueNotifier<bool>(false);

  /// 进入子界面时登记沉浸态。切标签页时壳层会自己复位，所以这里不用还原。
  static void enterSubView() => immersive.value = true;

  /// 退回上一级时恢复壳层顶栏。
  static void exitSubView() => immersive.value = false;
}
