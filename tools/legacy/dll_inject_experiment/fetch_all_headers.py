# -*- coding: utf-8 -*-
"""下载 CEF 91（Chromium branch 4472）全部 capi/internal/base 头文件。

CEF 的头互相 include（capi 会拉进几乎整个 capi 树），所以要整目录取全。
目录结构按 CEF 原样摆放：cef_root/include/{capi,internal,base}
"""
import json, os, urllib.request

BRANCH = '4472'
API = f'https://api.github.com/repos/chromiumembedded/cef/contents/include/{BRANCH}'
RAW = f'https://raw.githubusercontent.com/chromiumembedded/cef/{BRANCH}/include'
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, 'cef_root')

def api_list(sub):
    url = f'https://api.github.com/repos/chromiumembedded/cef/contents/include/{sub}?ref={BRANCH}'
    with urllib.request.urlopen(url, timeout=30) as r:
        return [x['name'] for x in json.load(r) if x['type'] == 'file']

def grab(sub, name):
    with urllib.request.urlopen(f'{RAW}/{sub}/{name}', timeout=30) as r:
        return r.read()

total = 0
for sub in ('capi', 'internal', 'base'):
    try:
        names = api_list(sub)
    except Exception as e:
        print('list fail', sub, e)
        continue
    d = os.path.join(ROOT, 'include', sub)
    os.makedirs(d, exist_ok=True)
    for n in names:
        p = os.path.join(d, n)
        if os.path.exists(p) and os.path.getsize(p) > 0:
            continue
        for attempt in range(3):
            try:
                data = grab(sub, n)
                open(p, 'wb').write(data)
                total += 1
                break
            except Exception:
                continue
    print(sub, len(names), 'files')
print('downloaded', total, 'new files ->', ROOT)