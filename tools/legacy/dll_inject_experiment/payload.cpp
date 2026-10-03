// E听说助手 · PC 注入 payload（自主实现）
//
// 链路：
//  1) 由软件侧的注入器（CreateRemoteThread + LoadLibrary）载入本 DLL，
//     不再劫持任何系统 DLL，不修改 E听说 安装目录；
//  2) 改写本进程 IAT，拦截 libcef 的 cef_browser_host_create_browser；
//  3) 包装 client 的 LifeSpanHandler，在 on_after_created 截获浏览器对象；
//  4) 把「软件远程下发的规则」+ inject.js 注入页面（execute_java_script
//     必须在 CEF UI 线程，用 cef_post_task(TID_UI) 投递）；
//  5) 状态回传本机软件（/report），让用户明确知道有没有生效。
//
// 只用公开技术：PE 导入表改写 / CEF 官方 C API。
#include <windows.h>
#include <winsock2.h>

// winmm 转发桩初始化（winmm_forward.cpp 自动生成）
extern "C" __declspec(dllexport) void WinmmProxyInit();
extern "C" __declspec(dllexport) void WinmmProxyUninit();

#include <string>
#include <thread>
#include <vector>


char g_envBuf[8] = {0};
#include "base/cef_macros.h"
#include "base/cef_ref_counted.h"
#include "internal/cef_string.h"
#include "internal/cef_string_types.h"
#include "capi/cef_browser_capi.h"
#include "capi/cef_client_capi.h"
#include "capi/cef_frame_capi.h"
#include "capi/cef_life_span_handler_capi.h"
#include "capi/cef_task_capi.h"

namespace {

#ifndef ETS_STAGE
#define ETS_STAGE 4
#endif

// ---------------- 日志 ----------------

std::wstring g_dir;

std::wstring SelfDir() {
  wchar_t path[MAX_PATH] = {0};
  ::GetModuleFileNameW(nullptr, path, MAX_PATH);
  std::wstring p(path);
  size_t pos = p.find_last_of(L"\\");
  return pos == std::wstring::npos ? std::wstring(L".") : p.substr(0, pos);
}

std::wstring Widen(const std::string& s) {
  if (s.empty()) return {};
  int n = ::MultiByteToWideChar(CP_UTF8, 0, s.data(),
                                static_cast<int>(s.size()), nullptr, 0);
  std::wstring w(n, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                        &w[0], n);
  return w;
}

std::string Narrow(const std::wstring& s) {
  if (s.empty()) return {};
  int n = ::WideCharToMultiByte(CP_UTF8, 0, s.data(),
                                static_cast<int>(s.size()), nullptr, 0,
                                nullptr, nullptr);
  std::string out(n, '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                        &out[0], n, nullptr, nullptr);
  return out;
}

void Log(const std::wstring& msg) {
  SYSTEMTIME st;
  ::GetLocalTime(&st);
  wchar_t line[2048];
  int n = ::swprintf(line, 2048, L"[%02d:%02d:%02d] %s\r\n", st.wHour,
                     st.wMinute, st.wSecond, msg.c_str());
  HANDLE h = ::CreateFileW((g_dir + L"\\ets_inject.log").c_str(),
                            FILE_APPEND_DATA, FILE_SHARE_READ, nullptr,
                            OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (h == INVALID_HANDLE_VALUE) return;
  DWORD w = 0;
  ::WriteFile(h, line, n * sizeof(wchar_t), &w, nullptr);
  ::CloseHandle(h);
}

bool IsEtsHost() {
  wchar_t path[MAX_PATH] = {0};
  ::GetModuleFileNameW(nullptr, path, MAX_PATH);
  std::wstring p(path);
  size_t pos = p.find_last_of(L"\\/");
  std::wstring name = pos == std::wstring::npos ? p : p.substr(pos + 1);
  for (auto& c : name) c = ::towlower(c);
  return name == L"etsshell.exe" || name == L"ets.exe" ||
         name == L"hd_ets.exe";
}

std::string ReadFileIfExists(const std::wstring& path) {
  HANDLE h = ::CreateFileW(path.c_str(), GENERIC_READ,
                           FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                           OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (h == INVALID_HANDLE_VALUE) return {};
  DWORD sz = ::GetFileSize(h, nullptr);
  if (sz == 0 || sz > 4 * 1024 * 1024) {
    ::CloseHandle(h);
    return {};
  }
  std::string buf(sz, '\0');
  DWORD read = 0;
  ::ReadFile(h, buf.data(), sz, &read, nullptr);
  buf.resize(read);
  ::CloseHandle(h);
  return buf;
}


// ---------------- CEF 字符串（UTF-16） ----------------
// CefString 包装类会静态引用 libcef 里的字符串函数，这里改为
// 直接操作 cef_string_utf16_t，转换用 Win32 API，避免链接期依赖。
std::wstring Utf16ToWide(const cef_string_utf16_t* s) {
  if (s == nullptr || s->str == nullptr || s->length == 0) return {};
  return std::wstring(reinterpret_cast<const wchar_t*>(s->str), s->length);
}

std::string Utf16ToUtf8(const cef_string_utf16_t* s) {
  std::wstring w = Utf16ToWide(s);
  if (w.empty()) return {};
  int n = ::WideCharToMultiByte(CP_UTF8, 0, w.data(),
                                static_cast<int>(w.size()), nullptr, 0,
                                nullptr, nullptr);
  std::string out(static_cast<size_t>(n), 0);
  ::WideCharToMultiByte(CP_UTF8, 0, w.data(), static_cast<int>(w.size()),
                        &out[0], n, nullptr, nullptr);
  return out;
}

// ---------------- 与软件的本地通道 ----------------

int g_rulesPort = 8848;
int g_injectCount = 0;
std::string g_lastUrl;
std::string g_lastRules;
CRITICAL_SECTION g_lock;
bool g_lockReady = false;

std::string SimpleRequest(int port, const std::string& method,
                          const char* path, const std::string& body = {}) {
  std::string req = method + " " + path +
                    " HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n"
                    "User-Agent: EtsHelperInject/1.0\r\n";
  if (!body.empty()) {
    req += "Content-Type: application/json\r\nContent-Length: " +
           std::to_string(body.size()) + "\r\n";
  }
  req += "\r\n" + body;
  SOCKET s = ::socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (s == INVALID_SOCKET) return {};
  sockaddr_in addr{};
  addr.sin_family = AF_INET;
  addr.sin_port = htons(static_cast<unsigned short>(port));
  addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  if (::connect(s, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) != 0) {
    ::closesocket(s);
    return {};
  }
  ::send(s, req.data(), static_cast<int>(req.size()), 0);
  std::string out;
  char buf[4096];
  DWORD t0 = ::GetTickCount();
  while (::GetTickCount() - t0 < 1500) {
    int n = ::recv(s, buf, sizeof(buf), 0);
    if (n <= 0) break;
    out.append(buf, n);
    if (out.size() > 1024 * 1024) break;
  }
  ::closesocket(s);
  size_t sep = out.find("\r\n\r\n");
  if (sep == std::string::npos) return {};
  return out.substr(sep + 4);
}

std::string JsonEscape(const std::string& in) {
  std::string o;
  for (char c : in) {
    if (c == '\\' || c == '"') {
      o.push_back('\\');
      o.push_back(c);
    } else if (static_cast<unsigned char>(c) < 0x20) {
      o.push_back('\0');
    } else {
      o.push_back(c);
    }
  }
  return o;
}

void ReportStatus(const std::wstring& note) {
  std::string b = "{\"build\":\"r1-inject\",\"injected\":" +
                  std::to_string(g_injectCount) + ",\"url\":\"" +
                  JsonEscape(g_lastUrl) + "\",\"note\":\"" +
                  JsonEscape(Narrow(note)) + "\"}";
  SimpleRequest(g_rulesPort, "POST", "/report", b);
}

// ---------------- 浏览器对象收集 ----------------

std::vector<struct _cef_browser_t*> g_browsers;
HANDLE g_injectThread = nullptr;
bool g_hooksInstalled = false;

void TrackBrowser(struct _cef_browser_t* browser) {
  if (browser == nullptr || !g_lockReady) return;
  ::EnterCriticalSection(&g_lock);
  for (auto* b : g_browsers) {
    if (b == browser) {
      ::LeaveCriticalSection(&g_lock);
      return;
    }
  }
  g_browsers.push_back(browser);
  ::LeaveCriticalSection(&g_lock);
  Log(L"捕获浏览器对象");
}

struct OurLifeSpan {
  _cef_life_span_handler_t handler;
  _cef_life_span_handler_t* inner;
};

// 已在原对象上打过补丁的 client（避免二次包装自己）
std::vector<_cef_client_t*> g_patched;
typedef _cef_life_span_handler_t*(CEF_CALLBACK* get_life_span_t)(
    struct _cef_client_t*);
get_life_span_t g_origGetLifeSpan = nullptr;
struct _cef_client_t* g_origClient = nullptr;

// CEF 91：add_ref 返回 void，release/has_* 返回 int，签名不同要分开实现
void CEF_CALLBACK NoopAddRef(cef_base_ref_counted_t*) {}
int CEF_CALLBACK NoopRef(cef_base_ref_counted_t*) { return 1; }

int CEF_CALLBACK StubBeforePopup(
    _cef_life_span_handler_t*, struct _cef_browser_t*, struct _cef_frame_t*,
    const cef_string_t*, const cef_string_t*, cef_window_open_disposition_t,
    int, const struct _cef_popup_features_t*, struct _cef_window_info_t*,
    struct _cef_client_t**, struct _cef_browser_settings_t*,
    struct _cef_dictionary_value_t**, int*) {
  return 0;
}
int CEF_CALLBACK StubDoClose(_cef_life_span_handler_t*,
                             struct _cef_browser_t*) {
  return 0;
}
void CEF_CALLBACK StubBeforeClose(_cef_life_span_handler_t*,
                                  struct _cef_browser_t*) {}

volatile struct _cef_browser_t* g_seenBrowser = nullptr;

void CEF_CALLBACK OnAfterCreated(_cef_life_span_handler_t* self,
                                 struct _cef_browser_t* browser) {
  // 只存指针：CEF UI 线程上不做加锁/写日志/容器分配，避免拖垮 UI 线程
  g_seenBrowser = browser;
  OurLifeSpan* me = reinterpret_cast<OurLifeSpan*>(self);
  if (me != nullptr && me->inner != nullptr &&
      me->inner->on_after_created != nullptr) {
    me->inner->on_after_created(me->inner, browser);
  }
}

struct _cef_life_span_handler_t* CEF_CALLBACK OurGetLifeSpan(
    struct _cef_client_t* self) {
  (void)self;
  static OurLifeSpan s;
  memset(&s.handler, 0, sizeof(s.handler));
  // 基类一律用我们自己的"永不释放"实现：绝不能复用 inner 的 retain/release，
  // 那样等于拿 inner 的对象去减 inner 的引用计数，会把它的 handler 提前释放掉。
  s.handler.base.add_ref = &NoopAddRef;
  s.handler.base.release = &NoopRef;
  s.handler.base.has_one_ref = &NoopRef;
  s.handler.base.has_at_least_one_ref = &NoopRef;
  if (g_origGetLifeSpan != nullptr && g_origClient != nullptr) {
    s.inner = g_origGetLifeSpan(g_origClient);
    if (s.inner != nullptr) {
      // 只搬回调（转发时 self 传 inner），不搬基类
      s.handler.on_before_popup = s.inner->on_before_popup;
      s.handler.do_close = s.inner->do_close;
      s.handler.on_before_close = s.inner->on_before_close;
    }
  }
  s.handler.on_after_created = &OnAfterCreated;
  return &s.handler;
}

// 指针是否落在 libcef.dll 的模块范围内——用来判断我们读到的函数指针
// 是不是合法（结构布局不匹配时读到的会是垃圾值）
bool LooksLikeCefCode(void* p) {
  if (p == nullptr) return false;
  MEMORY_BASIC_INFORMATION mbi{};
  if (::VirtualQuery(p, &mbi, sizeof(mbi)) == 0) return false;
  if (mbi.State != MEM_COMMIT) return false;
  // 必须是可执行页
  const DWORD x = mbi.Protect;
  return (x & (PAGE_EXECUTE | PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE |
               PAGE_EXECUTE_WRITECOPY)) != 0;
}

// 零拷贝包装：只替换原 client 上的一个 getter 指针。
// 绝不 memcpy 整个 client 结构——E听说 的 CEF 头布局与我们手上的不一致，
// 拷贝会越界把进程带崩。
struct _cef_client_t* MakeClient(struct _cef_client_t* inner) {
  if (inner == nullptr) return inner;
  for (auto* c : g_patched) {
    if (c == inner) return inner;  // 已包装
  }
  auto getter = inner->get_life_span_handler;
  if (!LooksLikeCefCode(reinterpret_cast<void*>(getter))) {
    Log(L"client 布局探测失败（getter 不在 libcef 内），本次不包装");
    return inner;
  }
  g_origGetLifeSpan = getter;
  g_origClient = inner;
  inner->get_life_span_handler = &OurGetLifeSpan;
  g_patched.push_back(inner);
  Log(L"client 已就地包装（零拷贝）");
  return inner;
}

// ---------------- CEF hook ----------------

typedef int(CEF_CALLBACK* create_browser_t)(
    const cef_window_info_t*, struct _cef_client_t*, const cef_string_t*,
    const struct _cef_browser_settings_t*, struct _cef_dictionary_value_t*,
    struct _cef_request_context_t*);
create_browser_t g_origCreateFn = nullptr;

int HookedCreate(const cef_window_info_t* wi, struct _cef_client_t* client,
                 const cef_string_t* url,
                 const struct _cef_browser_settings_t* st,
                 struct _cef_dictionary_value_t* extra,
                 struct _cef_request_context_t* ctx) {
#if ETS_STAGE >= 6
  int ret = g_origCreateFn(wi, CopyClientOnly(client), url, st, extra, ctx);
#elif ETS_STAGE >= 5
  int ret = g_origCreateFn(wi, MakeClient(client), url, st, extra, ctx);
#elif ETS_STAGE >= 4
  int ret = g_origCreateFn(wi, MakeClient(client), url, st, extra, ctx);
#else
  // 调试用：只验证钩子本身，不改 client
  int ret = g_origCreateFn(wi, client, url, st, extra, ctx);
#endif
  Log(L"命中 create_browser ret=" + std::to_wstring(ret));
  return ret;
}

// ---------------- UI 线程注入 ----------------

std::string g_pendingJs;
struct _cef_browser_t* g_pendingBrowser = nullptr;

int CEF_CALLBACK BaseRetain(cef_base_ref_counted_t*) { return 1; }
int CEF_CALLBACK BaseRelease(cef_base_ref_counted_t*) { return 1; }

struct OurTask {
  cef_task_t task;
};

OurTask g_task;

void CEF_CALLBACK TaskExecute(cef_task_t*) {
  if (g_pendingBrowser == nullptr || g_pendingJs.empty()) return;
  // UTF-8 -> UTF-16（脚本较大，堆分配并在执行后释放）
  int need = ::MultiByteToWideChar(CP_UTF8, 0, g_pendingJs.data(),
                                   static_cast<int>(g_pendingJs.size()), nullptr, 0);
  std::vector<char16> buf(need > 0 ? need : 1);
  if (need > 0) {
    ::MultiByteToWideChar(CP_UTF8, 0, g_pendingJs.data(),
                          static_cast<int>(g_pendingJs.size()), buf.data(), need);
  }
  cef_string_utf16_t code{};
  code.str = buf.data();
  code.length = static_cast<size_t>(need);
  cef_string_utf16_t srcUrl{};
  srcUrl.str = const_cast<char16*>(reinterpret_cast<const char16*>(L""));
  srcUrl.length = 0;
  struct _cef_frame_t* frame = g_pendingBrowser->get_main_frame(g_pendingBrowser);
  if (frame != nullptr && frame->is_valid(frame)) {
    frame->execute_java_script(frame, &code, &srcUrl, 0);
  }
  g_pendingJs.clear();
  g_pendingBrowser = nullptr;
}

// cef_post_task 运行时解析（避免链接期依赖 libcef）
int PostToUi() {
  static int (*fn)(cef_thread_id_t, cef_task_t*) = nullptr;
  if (fn == nullptr) {
    HMODULE cef = ::GetModuleHandleW(L"libcef.dll");
    if (cef == nullptr) return -1;
    fn = reinterpret_cast<int (*)(cef_thread_id_t, cef_task_t*)>(
        ::GetProcAddress(cef, "cef_post_task"));
  }
  if (fn == nullptr) return -1;
  return fn(TID_UI, &g_task.task);
}

void PostInject(struct _cef_browser_t* browser, const std::string& js) {
  g_pendingBrowser = browser;
  g_pendingJs = js;
  if (PostToUi() == 0) {
    ++g_injectCount;
    Log(L"已注入 #" + std::to_wstring(g_injectCount));
    ReportStatus(L"injected");
  } else {
    Log(L"cef_post_task 失败");
  }
}

DWORD WINAPI InjectThread(LPVOID) {
  Log(L"注入线程启动，规则端口=" + std::to_wstring(g_rulesPort));
  int warn = 0;
  while (true) {
    ::Sleep(600);

    std::string rules = SimpleRequest(g_rulesPort, "GET", "/rules");
    if (!rules.empty() && rules != g_lastRules) {
      g_lastRules = rules;
      Log(L"规则已更新（" + std::to_wstring(rules.size()) + L" 字节）");
    }

    std::string js = ReadFileIfExists(g_dir + L"\\inject.js");
    if (js.empty()) {
      if (++warn % 30 == 0) Log(L"未找到 inject.js");
      continue;
    }

    std::vector<struct _cef_browser_t*> browsers;
    if (g_seenBrowser != nullptr) browsers.push_back((struct _cef_browser_t*)g_seenBrowser);

    for (auto* browser : browsers) {
      if (browser == nullptr) continue;
      struct _cef_frame_t* frame = browser->get_main_frame(browser);
      if (frame == nullptr || !frame->is_valid(frame)) continue;
      cef_string_userfree_t rawUrl = frame->get_url(frame);
      std::string url = Utf16ToUtf8(rawUrl);
      if (rawUrl != nullptr) {
        typedef void(CEF_CALLBACK* free_fn)(cef_string_userfree_t);
        static free_fn s_free = reinterpret_cast<free_fn>(
            ::GetProcAddress(::GetModuleHandleW(L"libcef.dll"),
                             "cef_string_userfree_utf16_free"));
        if (s_free != nullptr) s_free(rawUrl);
      }
      if (url.empty()) continue;
      if (url == g_lastUrl && g_injectCount > 0) continue;

      std::string code = "window.__ETS_RULES__=" +
                         (g_lastRules.empty() ? std::string("null")
                                             : g_lastRules) +
                         ";\n" + js;
      PostInject(browser, code);
      g_lastUrl = url;
      Log(L"目标页面 " + Widen(url));
    }
  }
  return 0;
}

// ---- IAT 钩子 ----
// ETSShell.exe 静态导入 cef_browser_host_create_browser（libcef.dll），
// 直接改写导入表项即可拦截调用：无需 Detours/MinHook，
// 也不会冻结进程线程（CEF 加载期调用 EnableHook 会死锁）。
struct ThunkRow {
  union {
    void* fn;
    void** iat;
  };
};

struct ImportDesc {
  DWORD OriginalFirstThunk;
  DWORD TimeDateStamp;
  DWORD ForwarderChain;
  DWORD Name;
  DWORD FirstThunk;
};

// 在模块的导入表里找到指定函数的 IAT 项并替换
void* PatchIat(HMODULE mod, const char* dllName, const char* funcName,
               void* replacement) {
  BYTE* base = reinterpret_cast<BYTE*>(mod);
  auto* dos = reinterpret_cast<IMAGE_DOS_HEADER*>(base);
  auto* nt = reinterpret_cast<IMAGE_NT_HEADERS32*>(base + dos->e_lfanew);
  auto* dir = &nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
  if (dir->VirtualAddress == 0) return nullptr;
  auto* desc = reinterpret_cast<ImportDesc*>(base + dir->VirtualAddress);
  for (; desc->Name != 0; ++desc) {
    const char* cur = reinterpret_cast<const char*>(base + desc->Name);
    if (::_stricmp(cur, dllName) != 0) continue;
    // OriginalFirstThunk 可能为 0（导入名表缺失），此时只能用 FirstThunk
    DWORD namesRva = desc->OriginalFirstThunk != 0 ? desc->OriginalFirstThunk
                                                  : desc->FirstThunk;
    auto* names = reinterpret_cast<ThunkRow*>(base + namesRva);
    auto* iat = reinterpret_cast<ThunkRow*>(base + desc->FirstThunk);
    for (; names->fn != nullptr; ++names, ++iat) {
      if (reinterpret_cast<uintptr_t>(names->fn) & 0x80000000u) continue;  // 序号导入
      // thunk 里的值是 RVA，必须加模块基址才是绝对地址
      auto* hint = reinterpret_cast<IMAGE_IMPORT_BY_NAME*>(
          base + reinterpret_cast<uintptr_t>(names->fn));
      if (std::strcmp(reinterpret_cast<const char*>(hint->Name), funcName) != 0)
        continue;
      void* old = iat->fn;
      DWORD oldProtect = 0;
      ::VirtualProtect(iat, sizeof(void*), PAGE_READWRITE, &oldProtect);
      iat->fn = replacement;
      ::VirtualProtect(iat, sizeof(void*), oldProtect, &oldProtect);
      ::FlushInstructionCache(::GetCurrentProcess(), iat, sizeof(void*));
      return old;
    }
  }
  return nullptr;
}

void InstallCefHooks();  // 前置声明

// ---- LoadLibrary 包装：libcef.dll 一被映射就立刻改 CEF 的 IAT ----
// 直接改本进程 IAT（不用 MinHook，避免 EnableHook 冻结全进程线程导致死锁）
typedef HMODULE(WINAPI* LoadLibExW_t)(LPCWSTR, HANDLE, DWORD);
typedef HMODULE(WINAPI* LoadLibW_t)(LPCWSTR);
typedef HMODULE(WINAPI* LoadLibA_t)(LPCSTR);
LoadLibExW_t g_origLoadLibraryExW = nullptr;
LoadLibW_t g_origLoadLibraryW = nullptr;
LoadLibA_t g_origLoadLibraryA = nullptr;
bool g_loadHooked = false;

bool PathIsCef(const wchar_t* path) {
  return path != nullptr && ::wcsstr(path, L"libcef") != nullptr;
}
bool PathIsCef(const char* path) {
  return path != nullptr && ::strstr(path, "libcef") != nullptr;
}

HMODULE WINAPI HookedLoadLibraryExW(LPCWSTR path, HANDLE file, DWORD flags) {
  HMODULE m = g_origLoadLibraryExW(path, file, flags);
#if ETS_STAGE >= 3
  if (m != nullptr && PathIsCef(path)) InstallCefHooks();
#endif
  return m;
}

HMODULE WINAPI HookedLoadLibraryW(LPCWSTR path) {
  HMODULE m = g_origLoadLibraryW(path);
#if ETS_STAGE >= 3
  if (m != nullptr && PathIsCef(path)) InstallCefHooks();
#endif
  return m;
}

HMODULE WINAPI HookedLoadLibraryA(LPCSTR path) {
  HMODULE m = g_origLoadLibraryA(path);
#if ETS_STAGE >= 3
  if (m != nullptr && PathIsCef(path)) InstallCefHooks();
#endif
  return m;
}

void HookLoadLibrary() {
  if (g_loadHooked) return;
  HMODULE self = ::GetModuleHandleW(nullptr);
  HMODULE k32 = ::GetModuleHandleW(L"kernel32.dll");
  if (k32 == nullptr) return;
  void* old;
  old = PatchIat(self, "kernel32.dll", "LoadLibraryExW",
                 reinterpret_cast<void*>(&HookedLoadLibraryExW));
  if (old != nullptr) {
    g_origLoadLibraryExW = reinterpret_cast<LoadLibExW_t>(old);
  }
  old = PatchIat(self, "kernel32.dll", "LoadLibraryW",
                 reinterpret_cast<void*>(&HookedLoadLibraryW));
  if (old != nullptr) {
    g_origLoadLibraryW = reinterpret_cast<LoadLibW_t>(old);
  }
  old = PatchIat(self, "kernel32.dll", "LoadLibraryA",
                 reinterpret_cast<void*>(&HookedLoadLibraryA));
  if (old != nullptr) {
    g_origLoadLibraryA = reinterpret_cast<LoadLibA_t>(old);
  }
  g_loadHooked = true;
  Log(std::wstring(L"LoadLibrary IAT 已钩 ") +
      (g_origLoadLibraryExW ? L"ExW " : L"") +
      (g_origLoadLibraryW ? L"W " : L"") + (g_origLoadLibraryA ? L"A" : L""));
}

void InstallCefHooks() {
  if (g_hooksInstalled) return;
  HMODULE self = ::GetModuleHandleW(nullptr);
  void* old = PatchIat(self, "libcef.dll", "cef_browser_host_create_browser",
                      reinterpret_cast<void*>(&HookedCreate));
  if (old == nullptr) {
    Log(L"IAT 未找到 cef_browser_host_create_browser");
    return;
  }
  g_hooksInstalled = true;
  g_origCreateFn = reinterpret_cast<create_browser_t>(old);
  Log(L"IAT 钩子已安装");

  memset(&g_task, 0, sizeof(g_task));
  g_task.task.base.add_ref = &NoopAddRef;
  g_task.task.base.release = &NoopRef;
  g_task.task.base.has_one_ref = &BaseRetain;
  g_task.task.base.has_at_least_one_ref = &BaseRetain;
  g_task.task.execute = &TaskExecute;

  if (g_injectThread == nullptr) {
    g_injectThread = ::CreateThread(nullptr, 0, InjectThread, nullptr, 0, nullptr);
  }
}

DWORD WINAPI Worker(LPVOID) {
  Log(L"payload 线程启动" +
      std::wstring(IsEtsHost() ? L"（E听说 宿主）" : L"（非 E听说，退出）"));
  if (!IsEtsHost()) return 0;
#if ETS_STAGE == 1
  Log(L"[stage1] 只转发");
  return 0;
#endif
  WSADATA wsa;
  ::WSAStartup(MAKEWORD(2, 2), &wsa);


  // 先钩住 LoadLibrary：libcef.dll 映射进来的那一刻立刻改 CEF IAT，
  // 抢在 CEF 初始化建浏览器之前（否则会漏掉首个浏览器）
  HookLoadLibrary();
  for (int i = 0; i < 600; ++i) {
    if (::GetModuleHandleW(L"libcef.dll") != nullptr) {
      Log(L"检测到 libcef 加载");
#if ETS_STAGE >= 3
      InstallCefHooks();
      if (g_hooksInstalled) break;
#endif
    }
    ::Sleep(100);
  }
  if (!g_hooksInstalled) Log(L"未能安装 IAT 钩子");
  return 0;
}

}  // namespace

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID reserved) {
  (void)reserved;
  switch (reason) {
    case DLL_PROCESS_ATTACH: {
      ::DisableThreadLibraryCalls(module);
      // jmp 转发桩无空指针保护，必须在这里（任何人能调用我们之前）解析真实地址。
      // 加载的 winmm.dll 是系统已加载的模块，递归加锁是安全的。
      WinmmProxyInit();
      InitializeCriticalSection(&g_lock);
      g_lockReady = true;
      g_dir = SelfDir();
      ::CreateThread(nullptr, 0, Worker, nullptr, 0, nullptr);
      break;
    }
    case DLL_PROCESS_DETACH:
      break;
    default:
      break;
  }
  return TRUE;
}