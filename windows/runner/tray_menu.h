#ifndef RUNNER_TRAY_MENU_H_
#define RUNNER_TRAY_MENU_H_

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <functional>
#include <memory>
#include <string>
#include <vector>

namespace tray_menu {

// 托盘右键菜单项：label 为空且 separator=true 时画分隔线，danger 用警示色
struct Entry {
  std::string label;
  bool separator = false;
  bool danger = false;
};

// 接入 Flutter 通道：dart 侧 invoke('show', {items: [...]})
void Init(flutter::BinaryMessenger* messenger);

// 在鼠标位置弹出玻璃样式菜单；on_pick 回传被选项下标（关闭不回调）
void Show(const std::vector<Entry>& items,
          std::function<void(int)> on_pick);

void Close();

bool IsShown();

}  // namespace tray_menu

#endif  // RUNNER_TRAY_MENU_H_
