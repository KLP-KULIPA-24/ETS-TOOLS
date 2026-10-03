"""演示视频导出的文件接收器（配合 web/promo/promo.html?export=1 使用）。

监听 127.0.0.1:8902（默认；douyin_tray.exe 等程序可能占用 8901），接收 promo 页
导出产物并落盘到 web/docs/media/。用法：python tools/promo_receiver.py [端口=8902]
"""
import os
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "web", "docs", "media")
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8902


class Handler(BaseHTTPRequestHandler):
    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_POST(self):
        q = urllib.parse.urlparse(self.path)
        name = os.path.basename(urllib.parse.parse_qs(q.query).get("name", ["upload.bin"])[0])
        n = int(self.headers.get("Content-Length", 0))
        data = self.rfile.read(n)
        os.makedirs(OUT_DIR, exist_ok=True)
        out = os.path.join(OUT_DIR, name)
        with open(out, "wb") as f:
            f.write(data)
        self.send_response(200)
        self._cors()
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(("saved:" + out + ":" + str(n)).encode())

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    print("listening on 127.0.0.1:" + str(PORT) + " -> " + OUT_DIR, flush=True)
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
