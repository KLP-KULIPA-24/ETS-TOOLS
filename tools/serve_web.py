"""web 目录静态服务器（支持 HTTP Range——媒体拖动定位必需）。

python -m http.server 不支持 Range：video 的 seekable 为空、进度条拖不动，
所以本地验证演示视频请用本脚本：
    python tools/serve_web.py [端口=8899]
然后访问 http://127.0.0.1:8899/docs/index.html
"""
import os
import re
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "web")


class RangeHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def do_GET(self):
        rng = self.headers.get("Range")
        if not rng:
            return super().do_GET()
        m = re.match(r"bytes=(\d*)-(\d*)", rng.strip())
        path = self.translate_path(self.path)
        if not m or os.path.isdir(path) or not os.path.exists(path):
            return super().do_GET()
        size = os.path.getsize(path)
        start = int(m.group(1)) if m.group(1) else 0
        end = int(m.group(2)) if m.group(2) else size - 1
        end = min(end, size - 1)
        if start >= size or start > end:
            self.send_response(416)
            self.send_header("Content-Range", f"bytes */{size}")
            self.end_headers()
            return
        self.send_response(206)
        self.send_header("Content-Type", self.guess_type(path))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.send_header("Content-Length", str(end - start + 1))
        self.end_headers()
        with open(path, "rb") as f:
            f.seek(start)
            remaining = end - start + 1
            while remaining > 0:
                chunk = f.read(min(65536, remaining))
                if not chunk:
                    break
                self.wfile.write(chunk)
                remaining -= len(chunk)


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8899
    print(f"serving {ROOT} with Range support on http://127.0.0.1:{port}/docs/index.html")
    ThreadingHTTPServer(("127.0.0.1", port), RangeHandler).serve_forever()