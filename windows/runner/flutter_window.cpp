#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "tray_menu.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // 托盘右键自绘玻璃菜单（dart: lib/services/tray_menu_service.dart）
  tray_menu::Init(flutter_controller_->engine()->messenger());

  // 全局热键通道（dart: lib/services/hotkey_channel.dart）
  hotkey_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "eets/hotkey",
          &flutter::StandardMethodCodec::GetInstance());
  hotkey_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "setHotkey") {
          bool enabled = false;
          const auto* args = std::get_if<flutter::EncodableMap>(
              call.arguments());
          if (args != nullptr) {
            const auto it = args->find(flutter::EncodableValue("enabled"));
            if (it != args->end()) {
              enabled = std::get<bool>(it->second);
            }
          }
          SetHotkeyEnabled(enabled);
          result->Success();
          return;
        }
        result->NotImplemented();
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_HOTKEY:
      // Ctrl+Alt+E：通知 Dart 隐藏/显示窗口
      if (hotkey_channel_) {
        hotkey_channel_->InvokeMethod("hotkeyPressed", nullptr);
      }
      return 0;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::SetHotkeyEnabled(bool enabled) {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }
  if (enabled && !hotkey_registered_) {
    // MOD_NOREPEAT：长按不连发
    hotkey_registered_ =
        ::RegisterHotKey(hwnd, 1, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, 'E') != 0;
  } else if (!enabled && hotkey_registered_) {
    ::UnregisterHotKey(hwnd, 1);
    hotkey_registered_ = false;
  }
}
