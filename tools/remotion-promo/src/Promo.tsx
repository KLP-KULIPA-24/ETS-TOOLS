import React from "react";
import {
  AbsoluteFill,
  interpolate,
  Sequence,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";

export const FPS = 30;
export const SCENE_SEC = 6.2;
const SCENES = 10; // 开场 + 8 内容幕 + 收尾
export const TOTAL_FRAMES = Math.round(SCENES * SCENE_SEC * FPS);

/* ---------- 品牌令牌（与 docs/style-pack 一致：蓝紫深色） ---------- */
const C = {
  bg: "#0F1115",
  text: "#E6E8EC",
  muted: "#9AA1AC",
  primary: "#4F7CFF",
  border: "rgba(154,161,172,.38)",
  card: "rgba(23,26,33,.82)",
  serif: "Georgia, 'Times New Roman', 'Songti SC', 'SimSun', serif",
  sans: "'SF Pro Display','SF Pro Text','PingFang SC','Microsoft YaHei',sans-serif",
};

/* ---------- 通用动效 ---------- */
const useRise = (delay = 0, dy = 28) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = spring({ frame: frame - delay, fps, config: { damping: 200 }, durationInFrames: 34 });
  return {
    opacity: p,
    transform: `translateY(${(1 - p) * dy}px)`,
  };
};

const Rise: React.FC<React.PropsWithChildren<{ delay?: number; dy?: number; style?: React.CSSProperties }>> = ({
  delay = 0,
  dy = 28,
  style,
  children,
}) => {
  const s = useRise(delay, dy);
  return <div style={{ ...s, ...style }}>{children}</div>;
};

/* 世界坐标（设计稿 1920×1080）缩放到实际画布 */
const FIT: React.FC<React.PropsWithChildren<{ design?: number }>> = ({ design = 1920, children }) => {
  const { width } = useVideoConfig();
  const scale = width / design;
  return (
    <AbsoluteFill style={{ transform: `scale(${scale})`, transformOrigin: "top left", width: design, height: 1080 }}>
      {children}
    </AbsoluteFill>
  );
};

/* ---------- 舞台元素 ---------- */
const Stars: React.FC = () => {
  const pts = React.useMemo(
    () =>
      Array.from({ length: 130 }, (_, i) => ({
        x: (i * 137.51) % 1920,
        y: (i * 97.31) % 1080,
        r: 0.6 + ((i * 13) % 10) / 10,
        a: 0.12 + ((i * 7) % 10) / 26,
      })),
    []
  );
  return (
    <AbsoluteFill>
      {pts.map((p, i) => (
        <div
          key={i}
          style={{
            position: "absolute",
            left: p.x,
            top: p.y,
            width: p.r * 2,
            height: p.r * 2,
            borderRadius: 999,
            background: "#fff",
            opacity: p.a,
          }}
        />
      ))}
      {/* 顶部中央柔光（品牌色氛围） */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "radial-gradient(900px 520px at 50% 18%, rgba(79,124,255,.16), transparent 62%)," +
            "radial-gradient(1200px 700px at 86% 92%, rgba(79,124,255,.10), transparent 60%)",
        }}
      />
      {/* 暗角 */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          background: "radial-gradient(1100px 800px at 50% 50%, transparent 55%, rgba(0,0,0,.42))",
        }}
      />
    </AbsoluteFill>
  );
};

/* 品牌标（左上角常驻） */
const Brand: React.FC = () => (
  <div style={{ position: "absolute", left: 96, top: 76, display: "flex", alignItems: "center", gap: 16 }}>
    <div
      style={{
        width: 52,
        height: 52,
        borderRadius: 14,
        background: "linear-gradient(140deg,#5B9BFF,#3D6EF7)",
        display: "grid",
        placeItems: "center",
        boxShadow: "0 6px 22px rgba(79,124,255,.45)",
      }}
    >
      <span style={{ color: "#fff", fontWeight: 800, fontSize: 30, fontFamily: C.sans }}>E</span>
    </div>
    <span style={{ color: C.text, fontWeight: 600, fontSize: 32, fontFamily: C.sans, letterSpacing: "-.01em" }}>
      E听说助手
    </span>
  </div>
);

/* 底部进度条（主题色） */
const Progress: React.FC = () => {
  const frame = useCurrentFrame();
  const p = frame / TOTAL_FRAMES;
  return (
    <div style={{ position: "absolute", left: 0, right: 0, bottom: 0, height: 6, background: "rgba(255,255,255,.07)" }}>
      <div style={{ width: `${p * 100}%`, height: "100%", background: C.primary, boxShadow: "0 0 18px rgba(79,124,255,.6)" }} />
    </div>
  );
};

/* 眉标（大写小字 + 尾线） */
const Eyebrow: React.FC<{ text: string; delay?: number; center?: boolean }> = ({ text, delay = 0, center }) => (
  <Rise delay={delay} dy={18}>
    <div
      style={{
        display: "flex",
        alignItems: "center",
        gap: 18,
        justifyContent: center ? "center" : "flex-start",
        color: C.primary,
        fontFamily: C.sans,
        fontSize: 26,
        fontWeight: 600,
        letterSpacing: "0.14em",
      }}
    >
      <span>{text}</span>
      <span style={{ width: 28, height: 1, background: C.primary, opacity: 0.6 }} />
    </div>
  </Rise>
);

/* 大标题（衬线 = 出版级排版的"高级"） */
const Title: React.FC<{ text: string; delay?: number; size?: number }> = ({ text, delay = 6, size = 96 }) => (
  <Rise delay={delay} dy={34}>
    <div
      style={{
        fontFamily: C.serif,
        fontSize: size,
        lineHeight: 1.08,
        letterSpacing: "-.02em",
        color: C.text,
        textShadow: "0 6px 30px rgba(0,0,0,.5)",
      }}
    >
      {text}
    </div>
  </Rise>
);

const Sub: React.FC<{ text: string; delay?: number; width?: number; center?: boolean }> = ({
  text,
  delay = 12,
  width = 900,
  center,
}) => (
  <Rise delay={delay} dy={22}>
    <div
      style={{
        marginTop: 26,
        maxWidth: width,
        color: C.muted,
        fontFamily: C.sans,
        fontSize: 31,
        lineHeight: 1.6,
        textAlign: center ? "center" : "left",
      }}
    >
      {text}
    </div>
  </Rise>
);

const Chip: React.FC<{ text: string; delay: number }> = ({ text, delay }) => (
  <Rise delay={delay} dy={18}>
    <div
      style={{
        padding: "13px 26px",
        borderRadius: 999,
        border: `1px solid ${C.border}`,
        background: C.card,
        color: C.text,
        fontFamily: C.sans,
        fontSize: 26,
        whiteSpace: "nowrap",
      }}
    >
      {text}
    </div>
  </Rise>
);

const ChipRow: React.FC<{ chips: string[]; delay?: number; center?: boolean }> = ({ chips, delay = 22, center }) => (
  <div style={{ display: "flex", gap: 16, marginTop: 44, justifyContent: center ? "center" : "flex-start", flexWrap: "wrap" }}>
    {chips.map((c, i) => (
      <Chip key={c} text={c} delay={delay + i * 5} />
    ))}
  </div>
);

/* 通用内容容器 */
const Body: React.FC<React.PropsWithChildren<{ align?: "center" | "left" }>> = ({ align = "center", children }) => (
  <AbsoluteFill style={{ display: "flex", justifyContent: "center", alignItems: align === "center" ? "center" : "flex-start" }}>
    <div style={{ width: 1728, margin: "0 auto", paddingLeft: align === "center" ? 0 : 60, textAlign: align === "center" ? "center" : "left" }}>
      {children}
    </div>
  </AbsoluteFill>
);

/* ---------- 各幕 ---------- */
const SceneOpen: React.FC = () => (
  <Body>
    <Rise delay={0} dy={40}>
      <div style={{ fontFamily: C.serif, fontSize: 150, fontWeight: 600, letterSpacing: "-.02em", color: C.text, textShadow: "0 10px 40px rgba(0,0,0,.55)" }}>
        E听说助手
      </div>
    </Rise>
    <Rise delay={12} dy={26}>
      <div style={{ marginTop: 30, fontFamily: C.sans, fontSize: 34, color: C.muted, letterSpacing: ".02em" }}>
        答案 · 成绩修改 · <span style={{ color: C.text, fontWeight: 700 }}>AI 解析</span>，一次到位
      </div>
    </Rise>
    <ChipRow chips={["Windows", "Android", "本地优先"]} delay={26} center />
  </Body>
);

const Cards: React.FC<{ items: string[]; delay?: number }> = ({ items, delay = 20 }) => (
  <div style={{ display: "flex", gap: 18, marginTop: 48, justifyContent: "center", flexWrap: "wrap" }}>
    {items.map((t, i) => (
      <Rise key={t} delay={delay + i * 6} dy={26}>
        <div
          style={{
            width: 292,
            padding: "40px 0 34px",
            borderRadius: 22,
            background: C.card,
            border: `1px solid ${C.border}`,
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            gap: 22,
          }}
        >
          <div style={{ width: 14, height: 14, borderRadius: 999, background: C.primary, boxShadow: "0 0 16px rgba(79,124,255,.8)" }} />
          <div style={{ fontFamily: C.sans, fontSize: 30, color: C.text, fontWeight: 500 }}>{t}</div>
        </div>
      </Rise>
    ))}
  </div>
);

const SceneAnswers: React.FC = () => (
  <Body>
    <Eyebrow text="01 · 答案" center />
    <Title text="每种题，都有专属排版" delay={6} />
    <Sub text="支持背题模式，答案逐句对照。" delay={12} center width={1100} />
    <Cards items={["模仿朗读", "角色扮演", "故事复述", "对话跟读", "单词跟读"]} />
  </Body>
);

const SceneTweak: React.FC = () => (
  <Body align="left">
    <Eyebrow text="02 · 成绩修改" />
    <Title text="提交前的最后一道关" delay={6} />
    <Sub text="本地拦截引擎接管作业提交，命中同步接口即按规则改写成绩与完成时间，全程数据不出本机。" delay={12} width={860} />
    <ChipRow chips={["本地代理引擎", "成绩自定义", "时间自定义"]} />
  </Body>
);

const SceneAI: React.FC = () => (
  <Body align="left">
    <Eyebrow text="03 · AI 智能解析" />
    <Title text="不懂就问，问到懂" delay={6} />
    <Sub text="流式对话 · 全文翻译 · AI 标题，接任意 OpenAI 兼容接口" delay={12} width={880} />
    <ChipRow chips={["多提供商", "多模态", "思考档位"]} />
  </Body>
);

const SceneListen: React.FC = () => (
  <Body>
    <Eyebrow text="04 · 精听播放" center />
    <Title text="听清每一句" delay={6} />
    <ChipRow chips={["0.6–2.0 倍速", "A-B 循环", "逐句按时间轴播放"]} delay={18} center />
  </Body>
);

const SceneLocal: React.FC = () => (
  <Body align="left">
    <Eyebrow text="05 · 本地优先" />
    <Title text="数据本来就在你本机" delay={6} />
    <Sub text="扫描 E听说 客户端已下载的作业目录，不上传、不破解、不碰账号，解析全部在本机完成。" delay={12} width={860} />
    <ChipRow chips={["全离线可用", "无需登录", "免费开源"]} />
  </Body>
);

const SceneRead: React.FC = () => (
  <Body>
    <Eyebrow text="06 · 四种读取方式" center />
    <Title text="总有一条通道能走" delay={6} />
    <Sub text="Shizuku / Root / 直读 / SAF —— 四种安卓数据读取方式，适配各种机型与权限条件" delay={12} center width={1200} />
    <ChipRow chips={["Shizuku 免 Root", "Root 最高权限", "零提权直读", "SAF 系统授权"]} delay={20} center />
  </Body>
);

const SceneDual: React.FC = () => (
  <Body>
    <Eyebrow text="07 · 双端体验" center />
    <Title text="一套数据，两端同用" delay={6} />
    <div style={{ display: "flex", gap: 22, marginTop: 48, justifyContent: "center" }}>
      {[
        ["Windows", "10 / 11 · x64"],
        ["Android", "7.0 及以上"],
      ].map(([nm, sb], i) => (
        <Rise key={nm} delay={18 + i * 6} dy={26}>
          <div
            style={{
              width: 400,
              padding: "30px 0",
              borderRadius: 22,
              background: C.card,
              border: `1px solid ${C.border}`,
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              gap: 8,
            }}
          >
            <div style={{ fontFamily: C.sans, fontSize: 34, fontWeight: 700, color: C.text }}>{nm}</div>
            <div style={{ fontFamily: C.sans, fontSize: 22, color: C.muted }}>{sb}</div>
          </div>
        </Rise>
      ))}
    </div>
    <Sub text="悬浮窗常驻，做作业时随时唤起。" delay={34} center width={1200} />
  </Body>
);

const SceneService: React.FC = () => (
  <Body>
    <Eyebrow text="08 · 服务与工具" center />
    <Title text="配套工具，都备好了" delay={6} />
    <Sub text="AI 接口与 Android 提权——免费、够用、不折腾。" delay={12} center width={1200} />
    <ChipRow chips={["Agnes AI · 无限免费"]} delay={20} center />
  </Body>
);

const SceneEnd: React.FC = () => (
  <Body>
    <Rise delay={0} dy={40}>
      <div style={{ fontFamily: C.serif, fontSize: 150, fontWeight: 600, letterSpacing: "-.02em", color: C.text, textShadow: "0 10px 40px rgba(0,0,0,.55)" }}>
        E听说助手
      </div>
    </Rise>
    <Rise delay={12} dy={24}>
      <div style={{ marginTop: 26, fontFamily: C.sans, fontSize: 32, color: C.muted }}>本地优先 · 免费 · 仅供学习研究</div>
    </Rise>
    <div style={{ display: "flex", gap: 20, marginTop: 46, justifyContent: "center" }}>
      <Rise delay={22} dy={22}>
        <div
          style={{
            padding: "20px 44px",
            borderRadius: 999,
            background: C.primary,
            color: "#fff",
            fontFamily: C.sans,
            fontSize: 30,
            fontWeight: 600,
            boxShadow: "0 12px 34px rgba(79,124,255,.45), inset 0 1px 0 rgba(255,255,255,.3)",
          }}
        >
          ↓ 下载 Windows 版
        </div>
      </Rise>
      <Rise delay={28} dy={22}>
        <div
          style={{
            padding: "20px 44px",
            borderRadius: 999,
            background: C.card,
            border: `1px solid ${C.border}`,
            color: C.text,
            fontFamily: C.sans,
            fontSize: 30,
            fontWeight: 600,
          }}
        >
          ↓ 下载 Android 版
        </div>
      </Rise>
    </div>
    <Rise delay={40} dy={18}>
      <div style={{ marginTop: 40, fontFamily: C.sans, fontSize: 24, color: C.muted, letterSpacing: ".04em" }}>
        github.com/KLP-KULIPA-24
      </div>
    </Rise>
  </Body>
);

/* ---------- 幕切换（交叉淡入 + 微缩放） ----------
   注意：Sequence 内 useCurrentFrame() 返回的是**局部帧**（相对本幕起点），
   不要再减幕序号偏移（曾因此让第 2 幕起全部隐身）。 */
const Switch: React.FC<React.PropsWithChildren<Record<string, never>>> = ({ children }) => {
  const frame = useCurrentFrame();
  const dur = Math.round(SCENE_SEC * FPS);
  const inP = interpolate(frame, [0, 14], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const outP = interpolate(frame, [dur - 14, dur], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const o = Math.min(inP, outP);
  const scale = 1 + (1 - inP) * 0.015;
  if (o <= 0) return null;
  return (
    <AbsoluteFill style={{ opacity: o, transform: `scale(${scale})` }}>{children}</AbsoluteFill>
  );
};

export const Promo: React.FC = () => {
  const scenes: React.FC[] = [
    SceneOpen,
    SceneAnswers,
    SceneTweak,
    SceneAI,
    SceneListen,
    SceneLocal,
    SceneRead,
    SceneDual,
    SceneService,
    SceneEnd,
  ];
  return (
    <AbsoluteFill style={{ background: C.bg }}>
      <Stars />
      <Brand />
      {scenes.map((S, i) => (
        <Sequence key={i} from={Math.round(i * SCENE_SEC * FPS)} durationInFrames={Math.round(SCENE_SEC * FPS)}>
          <Switch>
            <S />
          </Switch>
        </Sequence>
      ))}
      <Progress />
    </AbsoluteFill>
  );
};
