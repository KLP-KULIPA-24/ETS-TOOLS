# -*- coding: utf-8 -*-
"""下载 CEF 91（Cephronium branch 4472）的 capi/internal/base 头文件。
只取我们用得到的少量头，避免 130MB 的完整二进制包。"""
import os, sys, urllib.request, json

BRANCH = '4472'
BASE = f'https://raw.githubusercontent.com/chromiumembedded/cef/{BRANCH}/include'
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'cef_include')

FILES = [
    'base/cef_macros.h',
    'base/cef_ref_counted.h',
    'base/cef_log_severity.h',
    'base/cef_scoped_refptr.h',
    'base/cef_bootstrap.h',
    'internal/cef_types.h',
    'internal/cef_types_win.h',
    'internal/cef_string.h',
    'internal/cef_win.h',
    'internal/cef_ptr.h',
    'capi/cef_client_capi.h',
    'capi/cef_string_capi.h',
    'capi/cef_voucher_capi.h',
    'capi/cef_v8_capi.h',
    'capi/cef_request_context_capi.h',
    'capi/cef_browser_capi.h',
    'capi/cef_frame_capi.h',
    'capi/cef_load_handler_capi.h',
    'capi/cef_app_capi.h',
    'capi/cef_browser_process_capi.h',
    'capi/cef_process_capi.h',
]

def fetch(path):
    url = f'{BASE}/{path}'
    try:
        with urllib.request.urlopen(url, timeout=30) as r:
            return r.read()
    except Exception as e:
        return None

os.makedirs(OUT, exist_ok=True)
ok, miss = 0, []
for f in FILES:
    data = fetch(f)
    if data is None:
        miss.append(f)
        continue
    dst = os.path.join(OUT, f)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(dst, 'wb') as out:
        out.write(data)
    ok += 1
    print('ok  ', f, len(data))
for m in miss:
    print('MISS', m)
print(f'done: {ok}/{len(FILES)}')