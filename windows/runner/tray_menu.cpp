#include "tray_menu.h"

#include <windows.h>
#include <windowsx.h>
#include <dwmapi.h>

#include <cmath>
#include <cstdio>
#include <string>
#include <vector>

namespace tray_menu {
namespace {

constexpr wchar_t kClassName[] = L"EtsHelperTrayMenuWindow";
constexpr UINT_PTR kKillTimerId = 1;
constexpr int kItemH = 40;
constexpr int kSepH = 13;
constexpr int kPadX = 10;
constexpr int kPadY = 8;
constexpr int kRadius = 14;
constexpr int kShadow = 14;
constexpr int kCapsuleInset = 6;

// 深/浅色玻璃配色（与 style-pack 观感一致：深蓝黑 / 亮白微透）
struct Palette {
  BYTE card_r, card_g, card_b, card_a;
  BYTE border_r, border_g, border_b, border_a;
  BYTE text_r, text_g, text_b;
  BYTE hover_r, hover_g, hover_b;  // 主色 #4F6BFF
  BYTE danger_r, danger_g, danger_b;
};

// ---- 诊断日志：%TEMP%\eets_traymenu.log（右键无反应时定位用） ----
void LogLine(const char* msg) {
  char tmp[MAX_PATH] = {0};
  if (::GetTempPathA(MAX_PATH, tmp) == 0) return;
  std::string path = std::string(tmp) + "eets_traymenu.log";
  FILE* fp = nullptr;
  if (fopen_s(&fp, path.c_str(), "a") != 0 || fp == nullptr) return;
  SYSTEMTIME st{};
  ::GetLocalTime(&st);
  fprintf(fp, "[%02d:%02d:%02d.%03d] %s\n", st.wHour, st.wMinute, st.wSecond,
          st.wMilliseconds, msg);
  fclose(fp);
}

Palette ReadPalette() {
  // AppsUseLightTheme：0=深色
  DWORD light = 0;
  HKEY key = nullptr;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER,
                      L"Software\\Microsoft\\Windows\\CurrentVersion\\"
                      L"Themes\\Personalize",
                      0, KEY_READ, &key) == ERROR_SUCCESS) {
    DWORD type = 0;
    DWORD cb = sizeof(light);
    ::RegQueryValueExW(key, L"AppsUseLightTheme", nullptr, &type,
                       reinterpret_cast<BYTE*>(&light), &cb);
    ::RegCloseKey(key);
  }
  Palette p{};
  if (light != 0) {
    p.card_r = 252; p.card_g = 252; p.card_b = 253; p.card_a = 246;
    p.border_r = 0; p.border_g = 0; p.border_b = 0; p.border_a = 30;
    p.text_r = 32; p.text_g = 34; p.text_b = 40;
    p.hover_r = 79; p.hover_g = 107; p.hover_b = 255;
    p.danger_r = 220; p.danger_g = 60; p.danger_b = 70;
  } else {
    p.card_r = 24; p.card_g = 26; p.card_b = 34; p.card_a = 236;
    p.border_r = 255; p.border_g = 255; p.border_b = 255; p.border_a = 40;
    p.text_r = 236; p.text_g = 238; p.text_b = 244;
    p.hover_r = 79; p.hover_g = 107; p.hover_b = 255;
    p.danger_r = 255; p.danger_g = 120; p.danger_b = 130;
  }
  return p;
}

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return std::wstring();
  int n = ::MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, nullptr, 0);
  if (n <= 0) return std::wstring();
  std::wstring w(static_cast<size_t>(n), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, &w[0], n);
  if (!w.empty() && w.back() == L'\0') w.pop_back();
  return w;
}

int ToRgb(const Palette& p, const Entry& e, bool hover) {
  if (hover) {
    return (p.hover_r << 16) | (p.hover_g << 8) | p.hover_b;
  }
  if (e.danger) {
    return (p.danger_r << 16) | (p.danger_g << 8) | p.danger_b;
  }
  return (p.text_r << 16) | (p.text_g << 8) | p.text_b;
}

struct Surface {
  HDC dc = nullptr;
  HBITMAP bmp = nullptr;
  HGDIOBJ old_bmp = nullptr;
  uint32_t* px = nullptr;
  int w = 0;
  int h = 0;
};

Surface MakeSurface(int w, int h) {
  Surface s;
  s.w = w;
  s.h = h;
  BITMAPINFO bi{};
  bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bi.bmiHeader.biWidth = w;
  bi.bmiHeader.biHeight = -h;  // top-down
  bi.bmiHeader.biPlanes = 1;
  bi.bmiHeader.biBitCount = 32;
  bi.bmiHeader.biCompression = BI_RGB;
  s.dc = ::CreateCompatibleDC(nullptr);
  void* bits = nullptr;
  s.bmp = ::CreateDIBSection(s.dc, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
  s.px = static_cast<uint32_t*>(bits);
  s.old_bmp = ::SelectObject(s.dc, s.bmp);
  return s;
}

void FreeSurface(Surface& s) {
  if (s.dc) {
    ::SelectObject(s.dc, s.old_bmp);
    ::DeleteObject(s.bmp);
    ::DeleteDC(s.dc);
    s = Surface{};
  }
}

// 圆角矩形有符号距离：d>0 在内部
float RoundRectSdf(float x, float y, float l, float t, float r, float b,
                   float radius) {
  const float cx = (l + r) * 0.5f, cy = (t + b) * 0.5f;
  const float hx = (r - l) * 0.5f, hy = (b - t) * 0.5f;
  const float qx = std::fabs(x - cx) - (hx - radius);
  const float qy = std::fabs(y - cy) - (hy - radius);
  const float outside =
      std::sqrt(std::max(qx, 0.f) * std::max(qx, 0.f) +
                std::max(qy, 0.f) * std::max(qy, 0.f));
  const float inside = std::min(std::max(qx, qy), 0.f);
  return radius - (outside + inside);
}

// 以预乘 alpha 做 source-over 合成（UpdateLayeredWindow 需要预乘像素）
void Blend(uint32_t* px, BYTE sr, BYTE sg, BYTE sb, float sa) {
  if (sa <= 0.f) return;
  if (sa > 1.f) sa = 1.f;
  const uint32_t dst = *px;
  const float da = ((dst >> 24) & 0xFF) / 255.f;
  const float inv = 1.f - sa;
  const float oa = sa + da * inv;
  if (oa <= 0.f) {
    *px = 0;
    return;
  }
  const auto mix = [&](int s, int shift) {
    const float d = ((dst >> shift) & 0xFF) / 255.f;  // 已是预乘
    const float v = (s / 255.f) * sa + d * inv;
    return static_cast<BYTE>(std::min(255.f, std::max(0.f, v * 255.f)));
  };
  *px = (static_cast<BYTE>(std::min(255.f, oa * 255.f)) << 24) |
        (mix(sr, 16) << 16) | (mix(sg, 8) << 8) | mix(sb, 0);
}

std::vector<Entry> g_items;
std::vector<RECT> g_hit;
int g_hover = -1;
HWND g_hwnd = nullptr;
int g_w = 0, g_h = 0;
std::function<void(int)> g_on_pick;
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_channel;
Surface g_surface;

void Finish(int index) {
  HWND hwnd = g_hwnd;
  g_hwnd = nullptr;
  g_hover = -1;
  g_hit.clear();
  g_items.clear();
  FreeSurface(g_surface);
  if (hwnd != nullptr) {
    ::DestroyWindow(hwnd);
  }
  if (index >= 0 && g_on_pick) {
    auto cb = g_on_pick;
    g_on_pick = nullptr;
    cb(index);
  } else {
    g_on_pick = nullptr;
    if (g_channel) {
      g_channel->InvokeMethod("menuClosed", nullptr);
    }
  }
}

int HitTest(int x, int y) {
  POINT pt{x, y};
  for (size_t i = 0; i < g_hit.size(); ++i) {
    if (PtInRect(&g_hit[i], pt)) return static_cast<int>(i);
  }
  return -1;
}

void Paint() {
  if (g_hwnd == nullptr || g_surface.px == nullptr) return;
  const Palette pal = ReadPalette();
  Surface& s = g_surface;
  const int card_l = kShadow, card_t = kShadow;
  const int card_r = s.w - kShadow, card_b = s.h - kShadow;

  // 1) 先铺背景（含阴影、卡片、hover 胶囊、分隔线），保留 alpha 供文字合成
  const float card_alpha = pal.card_a / 255.f;
  const float border_band = 1.4f;
  for (int y = 0; y < s.h; ++y) {
    for (int x = 0; x < s.w; ++x) {
      const float fx = x + 0.5f, fy = y + 0.5f;
      const float d = RoundRectSdf(fx, fy, static_cast<float>(card_l),
                                   static_cast<float>(card_t),
                                   static_cast<float>(card_r),
                                   static_cast<float>(card_b),
                                   static_cast<float>(kRadius));
      uint32_t* p = &s.px[y * s.w + x];
      if (d < -static_cast<float>(kShadow)) {
        *p = 0;  // 完全透明
        continue;
      }
      if (d < 0.f) {
        // 外阴影：距离越近越浓
        const float t = 1.f + d / static_cast<float>(kShadow);
        const float a = 70.f * t * t * t;
        Blend(p, 0, 0, 0, a / 255.f);
        continue;
      }
      // 卡片主体
      Blend(p, pal.card_r, pal.card_g, pal.card_b, card_alpha);
      // 描边
      if (d < border_band) {
        Blend(p, pal.border_r, pal.border_g, pal.border_b,
              (pal.border_a / 255.f) * (1.f - d / border_band));
      }
      // hover 胶囊
      if (g_hover >= 0 && g_hover < static_cast<int>(g_hit.size())) {
        RECT r = g_hit[g_hover];
        const float ci = RoundRectSdf(fx, fy,
                                      static_cast<float>(r.left + kCapsuleInset),
                                      static_cast<float>(r.top + 3),
                                      static_cast<float>(r.right - kCapsuleInset),
                                      static_cast<float>(r.bottom - 3), 11.f);
        if (ci > 0.f) {
          Blend(p, pal.hover_r, pal.hover_g, pal.hover_b, 0.34f * ci);
        }
      }
    }
  }
  // 分隔线
  for (size_t i = 0; i < g_items.size(); ++i) {
    if (!g_items[i].separator || i >= g_hit.size()) continue;
    const RECT& r = g_hit[i];
    const int ymid = (r.top + r.bottom) / 2;
    for (int x = card_l + 10; x <= card_r - 10; ++x) {
      const float d = RoundRectSdf(
          x + 0.5f, ymid + 0.5f, static_cast<float>(card_l),
          static_cast<float>(card_t), static_cast<float>(card_r),
          static_cast<float>(card_b), static_cast<float>(kRadius));
      if (d <= 0.f) continue;
      uint32_t* p = &s.px[ymid * s.w + x];
      Blend(p, pal.border_r, pal.border_g, pal.border_b, 0.28f);
    }
  }

  // 2) 文字层：先把 alpha 拍平为 255，GDI 画字后按 alpha 还原（预乘修正）
  const int total = s.w * s.h;
  std::vector<uint8_t> alpha(total);
  std::vector<uint32_t> flat(total);
  for (int i = 0; i < total; ++i) {
    const uint32_t v = s.px[i];
    alpha[i] = static_cast<uint8_t>((v >> 24) & 0xFF);
    flat[i] = 0xFF000000u | (v & 0x00FFFFFFu);
    s.px[i] = flat[i];
  }
  ::SetBkMode(s.dc, TRANSPARENT);
  HFONT font = ::CreateFontW(
      -16, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
      OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
      DEFAULT_PITCH, L"Microsoft YaHei UI");
  HFONT old_font = static_cast<HFONT>(::SelectObject(s.dc, font));
  ::SetTextColor(s.dc, RGB(pal.text_r, pal.text_g, pal.text_b));
  for (size_t i = 0; i < g_items.size(); ++i) {
    if (g_items[i].separator || i >= g_hit.size()) continue;
    const RECT& r = g_hit[i];
    const std::wstring label = Utf8ToWide(g_items[i].label);
    RECT tr = r;
    tr.left += kPadX + 4;
    tr.right -= 8;
    const int rgb = ToRgb(pal, g_items[i], g_hover == static_cast<int>(i));
    ::SetTextColor(s.dc, static_cast<COLORREF>(rgb));
    ::DrawTextW(s.dc, label.c_str(), static_cast<int>(label.size()), &tr,
                DT_SINGLELINE | DT_VCENTER | DT_NOPREFIX);
  }
  ::SelectObject(s.dc, old_font);
  ::DeleteObject(font);

  // 3) 还原：GDI 未改动的像素保持原有半透明；被改动的按不透明文字处理
  for (int i = 0; i < total; ++i) {
    const uint32_t now = s.px[i] & 0x00FFFFFFu;
    if (now == (flat[i] & 0x00FFFFFFu)) {
      s.px[i] = flat[i];  // 未变动：用拍平色（alpha=255，避免 GDI 清 alpha）
    } else {
      s.px[i] = 0xFF000000u | now;  // 文字像素
    }
  }
}

void Apply() {
  if (g_hwnd == nullptr || g_surface.px == nullptr) return;
  POINT pt{0, 0};
  ::ClientToScreen(g_hwnd, &pt);
  SIZE sz{g_surface.w, g_surface.h};
  BLENDFUNCTION blend{AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
  HDC screen = ::GetDC(nullptr);
  ::UpdateLayeredWindow(g_hwnd, screen, &pt, &sz, g_surface.dc, nullptr, 0,
                       &blend, ULW_ALPHA);
  ::ReleaseDC(nullptr, screen);
}

void ShowAt(int x, int y) {
  if (g_hwnd != nullptr) {
    Finish(-1);
  }
  int h = kPadY * 2;
  g_hit.clear();
  g_hover = -1;
  for (size_t i = 0; i < g_items.size(); ++i) {
    const int row_h = g_items[i].separator ? kSepH : kItemH;
    RECT r{kPadX, h, g_w - kPadX, h + row_h};
    g_hit.push_back(r);
    h += row_h;
  }
  g_hwnd = ::CreateWindowExW(WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TOOLWINDOW,
                             kClassName, L"", WS_POPUP, x, y, g_w, h, nullptr,
                             nullptr, nullptr, nullptr);
  if (g_hwnd == nullptr) {
    LogLine("CreateWindowExW FAILED -> fallback to system menu");
    g_items.clear();
    g_hit.clear();
    return;
  }
  LogLine("menu window created + shown");
  ::ShowWindow(g_hwnd, SW_SHOWNOACTIVATE);
  ::SetWindowPos(g_hwnd, HWND_TOPMOST, x, y, g_w, h,
                 SWP_NOACTIVATE | SWP_SHOWWINDOW);
  ::SetForegroundWindow(g_hwnd);
  Paint();
  Apply();
}

LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
  switch (msg) {
    case WM_MOUSEMOVE: {
      const int idx = HitTest(LOWORD(lp), HIWORD(lp));
      if (idx != g_hover) {
        g_hover = idx;
        Paint();
        Apply();
      }
      TRACKMOUSEEVENT tme{sizeof(TRACKMOUSEEVENT), TME_LEAVE, hwnd, 0};
      ::TrackMouseEvent(&tme);
      return 0;
    }
    case WM_MOUSELEAVE: {
      if (g_hover != -1) {
        g_hover = -1;
        Paint();
        Apply();
      }
      return 0;
    }
    case WM_LBUTTONUP: {
      const int idx = HitTest(static_cast<int>(GET_X_LPARAM(lp)),
                               static_cast<int>(GET_Y_LPARAM(lp)));
      if (idx >= 0) {
        Finish(idx);
      } else {
        Finish(-1);
      }
      return 0;
    }
    case WM_LBUTTONDOWN:
      return 0;
    case WM_KEYDOWN: {
      if (wp == VK_ESCAPE || wp == VK_CANCEL) {
        Finish(-1);
        return 0;
      }
      break;
    }
    case WM_SETFOCUS:
      ::KillTimer(hwnd, kKillTimerId);
      return 0;
    case WM_KILLFOCUS:
      // 350ms 宽限再关：与 SetForegroundWindow 的激活竞态/托盘焦点
      // 抢占不再导致菜单闪现即消失（"右键没反应"的疑点之一）
      ::SetTimer(hwnd, kKillTimerId, 350, nullptr);
      return 0;
    case WM_TIMER:
      if (wp == kKillTimerId) {
        ::KillTimer(hwnd, kKillTimerId);
        LogLine("auto-close after focus loss");
        Finish(-1);
        return 0;
      }
      break;
    case WM_ERASEBKGND:
      return 1;
    case WM_DESTROY:
      return 0;
    default:
      break;
  }
  return ::DefWindowProcW(hwnd, msg, wp, lp);
}

void EnsureClass() {
  static bool registered = false;
  if (registered) return;
  WNDCLASSEXW wc{};
  wc.cbSize = sizeof(WNDCLASSEXW);
  wc.lpfnWndProc = WndProc;
  wc.hInstance = ::GetModuleHandleW(nullptr);
  wc.lpszClassName = kClassName;
  ::RegisterClassExW(&wc);
  registered = true;
}

void ComputeSize() {
  int h = kPadY * 2 + kShadow * 2;
  for (const auto& e : g_items) {
    h += e.separator ? kSepH : kItemH;
  }
  g_w = 208 + kShadow * 2;
  g_h = h;
}

}  // namespace

void Init(flutter::BinaryMessenger* messenger) {
  g_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "eets/traymenu", &flutter::StandardMethodCodec::GetInstance());
  g_channel->SetMethodCallHandler(
      std::function<void(
          const flutter::MethodCall<flutter::EncodableValue>&,
          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>)>(
          [](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<
                 flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "show") {
          result->NotImplemented();
          return;
        }
        std::vector<Entry> items;
        // EncodableValue 是包装类，需转成内部 variant 才能 std::get_if
        const auto* args_ptr =
            call.arguments() == nullptr
                ? nullptr
                : std::get_if<flutter::EncodableMap>(
                      static_cast<const flutter::internal::EncodableValueVariant*>(
                          call.arguments()));
        if (args_ptr != nullptr) {
          const auto it = args_ptr->find(flutter::EncodableValue("items"));
          if (it != args_ptr->end()) {
            const auto* list = std::get_if<flutter::EncodableList>(
                static_cast<const flutter::internal::EncodableValueVariant*>(
                    &it->second));
            if (list != nullptr) {
              for (const auto& v : *list) {
                const auto* m = std::get_if<flutter::EncodableMap>(
                    static_cast<const flutter::internal::EncodableValueVariant*>(
                        &v));
                if (m == nullptr) continue;
                Entry e;
                const auto lit = m->find(flutter::EncodableValue("label"));
                if (lit != m->end()) {
                  const auto* s = std::get_if<std::string>(
                      static_cast<const flutter::internal::EncodableValueVariant*>(
                          &lit->second));
                  if (s != nullptr) e.label = *s;
                }
                const auto sit = m->find(flutter::EncodableValue("separator"));
                if (sit != m->end()) {
                  const auto* b = std::get_if<bool>(
                      static_cast<const flutter::internal::EncodableValueVariant*>(
                          &sit->second));
                  e.separator = b != nullptr && *b;
                }
                const auto dit = m->find(flutter::EncodableValue("danger"));
                if (dit != m->end()) {
                  const auto* b = std::get_if<bool>(
                      static_cast<const flutter::internal::EncodableValueVariant*>(
                          &dit->second));
                  e.danger = b != nullptr && *b;
                }
                items.push_back(e);
              }
            }
          }
        }
        g_items = std::move(items);
        ComputeSize();
        EnsureClass();
        FreeSurface(g_surface);
        g_surface = MakeSurface(g_w, g_h);

        POINT cursor{};
        ::GetCursorPos(&cursor);
        RECT wa{};
        if (::SystemParametersInfoW(SPI_GETWORKAREA, 0, &wa, 0)) {
          if (cursor.x + g_w > wa.right) cursor.x = wa.right - g_w;
          if (cursor.y + g_h > wa.bottom) cursor.y = cursor.y - g_h - 8;
          if (cursor.x < wa.left) cursor.x = wa.left;
          if (cursor.y < wa.top) cursor.y = wa.top;
        }
        ShowAt(cursor.x, cursor.y);
        const bool shown = g_hwnd != nullptr;
        if (!shown) {
          g_items.clear();
          g_hit.clear();
        }
        result->Success(flutter::EncodableValue(shown));
      }));
}

void Show(const std::vector<Entry>& items, std::function<void(int)> on_pick) {
  g_items = items;
  g_on_pick = std::move(on_pick);
  ComputeSize();
  EnsureClass();
  FreeSurface(g_surface);
  g_surface = MakeSurface(g_w, g_h);
  POINT cursor{};
  ::GetCursorPos(&cursor);
  RECT wa{};
  if (::SystemParametersInfoW(SPI_GETWORKAREA, 0, &wa, 0)) {
    if (cursor.x + g_w > wa.right) cursor.x = wa.right - g_w;
    if (cursor.y + g_h > wa.bottom) cursor.y = cursor.y - g_h - 8;
    if (cursor.x < wa.left) cursor.x = wa.left;
    if (cursor.y < wa.top) cursor.y = wa.top;
  }
  ShowAt(cursor.x, cursor.y);
}

void Close() {
  Finish(-1);
}

bool IsShown() {
  return g_hwnd != nullptr;
}

}  // namespace tray_menu
