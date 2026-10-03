"""REEL CONFIG — E听说助手 · 15 秒宣传片（标本 / 图录 牌）。

视觉语言：博物馆图录的一页——中性米灰底板、衬线标题、等宽编号、测量标注。
强调色为品牌实测值 #4F7CFF（docs/style-pack/tokens.json），不是凭感觉挑的。
"""

# --- identity ---------------------------------------------------------------
BRAND = "E听说助手"
DOMAIN = "github.com/KLP-KULIPA-24"
PRODUCT = "E听说"
STUDIO = "E听说助手"
PLATFORMS = "WINDOWS · ANDROID"
TAGLINE = "答案 · 成绩修改 · AI 解析"

# --- timeline ---------------------------------------------------------------
# 15.000 s exactly. One scene per bar, every cut lands on a downbeat.
#   8 bars -> 128 BPM | 6 bars -> 96 | 5 bars -> 80 | 4 bars -> 64
FPS = 30
BPM = 128
BEAT = 60.0 / BPM          # 0.46875 s
BAR = BEAT * 4             # 1.875 s
BARS = 8
DUR = BAR * BARS           # 15.000 s
NFRAMES = int(round(DUR * FPS))   # 450

# 浅色图录牌：直接在交付尺寸上排版（纸纹类细节要原生清晰）
OUT_W, OUT_H = 1920, 1080
W, H = 1280, 720

# --- palette（标本图录：中性米灰 + 一个强调色）--------------------------------
INK = (28, 27, 25)         # 最深墨色（标题/标本轮廓）
BG0 = (233, 231, 226)      # 底板：中性米灰 #E9E7E2
BG1 = (226, 223, 216)
BG2 = (216, 213, 205)

ACCENT = (79, 124, 255)    # 品牌主色 #4F7CFF（token 实测值）
ACCENT_BR = (126, 160, 255)  # 主色推向辉光
ACCENT_LT = (196, 209, 255)  # 主色浅调
ACCENT_DK = (52, 84, 190)

ALT = (196, 150, 60)       # 次强调（图录里的金褐，仅点缀）
INFO = (62, 118, 200)
WARN = (196, 124, 48)
ERR = (176, 62, 52)

WHITE = (16, 15, 14)   # 浅底图录牌：WHITE 即墨色（场景白字全部落到纸上）
PAPER = (233, 231, 226)    # 图录纸面
CARD = (242, 240, 235)
GREY = (122, 118, 110)
GREY_D = (74, 71, 66)
SLATE = (44, 42, 39)

# --- type -------------------------------------------------------------------
S_HERO = 118.0
S_WORD = 132.0
S_MONO = 96.0
S_LOGOTYPE = 54.0
S_SUB = 17.0
S_HUD = 9.5
S_TAG = 10.5

TRACK_HERO = -2.0
TRACK_WORD = -2.5
TRACK_SUB = 2.6
TRACK_HUD = 1.6

# --- HUD chrome -------------------------------------------------------------
M = 58.0           # live-area margin for panel-style layouts
HUD_M = 27.0
HUD_TOP = 24.0
HUD_BOT = 700.0

SCENES = [
    ("01", "标本 01",    "E听说助手"),
    ("02", "核心",       "答案 / 成绩修改 / AI 解析"),
    ("03", "标本 02",    "本机数据"),
    ("04", "读数",       "作业面板"),
    ("05", "链路",       "拦截引擎"),
    ("06", "图版",       "五种题型"),
    ("07", "通道",       "四种读取方式"),
    ("08", "收尾",       "获取方式"),
]

KINETIC_WORDS = ["答案", "成绩", "修改", "AI 解析"]
KINETIC_SUBS = [
    "五种题型 · 逐句对照",
    "拦截引擎 · 规则改写",
    "成绩与时间由你定义",
    "一次到位",
]

# readouts for the data scene — 作业面板语义
GAUGES = [("完成", 0.42, ACCENT), ("正确", 0.61, ACCENT), ("订正", 0.73, WARN),
          ("收藏", 0.28, INFO)]
METRICS = [("作业", "05"), ("题型", "05"), ("题量", "38"), ("端", "02")]
