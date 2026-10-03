# E听说助手

一个本地优先的 **E听说（讯飞英语听说）作业助手**，支持 **Windows** 与 **Android**。
直接解析 E听说客户端已下载到本地的作业数据，无需登录、不上传任何数据；
AI 功能仅在用户自行配置接口后由用户主动触发。仅供学习研究使用。

**作者：苦力怕.KULIPA** · [GitHub @KLP-KULIPA-24](https://github.com/KLP-KULIPA-24)

## 功能总览

| 功能 | 说明 |
| --- | --- |
| 作业列表 | 递归扫描 ETS 数据目录，按"文件夹名（数字）- 标题 - 类别"收纳，同类多条折叠为文件夹；单词组进入单词本页（可隐藏释义自测） |
| 答案查看 | 五种题型专属渲染：单词跟读 / 朗读短文 / 三问五答 / 看图说话 / 对话跟读；背题模式一键隐藏全部答案 |
| 标题三级策略 | ① 模板提取（paper.Jason `tz_mc`、`topic`、`read_title`）→ ② 自适应匹配 → ③ AI 智能匹配 |
| 精听播放 | 倍速 0.6x–2.0x、A-B 循环；逐句按 `begintime~endtime` 区间播放 |
| 多提供商 AI | 任意 OpenAI 兼容接口；每个提供商可配多个模型；模型支持**思考开关 + 思考级别（低/中/高）**与**多模态（图片输入）**；流式输出 |
| AI 实时对话 | 详情页"AI 对话"入口，多轮流式对话，可附图片，历史持久化 |
| AI 智能排版 | 智能解析 / 全文翻译 / AI 标题 / 未知题型 AI 自适应识别，结果缓存 |
| 模拟考场 | 按 ctrl 流程复现考试：播放→倒计时→录音→回放，支持中途跳过 |
| Android 悬浮窗 | 折叠为圆形 Logo，点击展开：答案速览 / 播放控制 / AI 实时快问 |
| Windows 悬浮窗 | 一键切换悬浮模式：主窗口变无边框置顶小圆，展开玻璃面板（同上），可拖动 |
| 修改栏（预留） | 抓包拦截 → 自动改写（成绩/时间测试）的配置骨架：监听端口、拦截规则、HTTPS 证书指引；拦截引擎待抓包数据接入 |
| 软件风格 | 默认 Material 3 风格 / **iOS 26 玻璃模糊风格**一键切换；主题色板 + 色相滑条自定义颜色；深浅色 |

## 数据目录

应用自动扫描以下位置（可在"设置"中追加）：

- **Windows**：`%APPDATA%\ETS`（即 `C:\Users\<用户>\AppData\Roaming\ETS`）
- **Android**：`/storage/emulated/0/Android/data/com.ets100.secondary/files/Download/ETS_secondary/resource`
  （需要授予"所有文件访问"权限）

### Android 11+ 读不了 Android/data？（重要）

Android 11+ 限制读取**其他应用**的 `Android/data` 目录，即使授予"所有文件访问"也不行。
APP 内置了提权提取通道（设置 → 数据目录 → 数据提取）：

| 通道 | 适用 | 步骤 |
| --- | --- | --- |
| **Root**（libsu） | Mumu 模拟器、已 root 真机 | Mumu 设置 → 其他设置 → 开启 ROOT，回到本 APP 点"一键提取作业数据" |
| **Shizuku** | 免 root 真机 | 安装 Shizuku → 开发者选项打开无线调试 → Shizuku 配对启动 → 回本 APP 点"授权 Shizuku"→"一键提取" |

提取会把 E听说 数据拷贝到本应用私有目录（`Android/data/com.eets.e_ets_helper/files/ets_data`），
之后扫描、精听、悬浮窗全部正常，且每次 E听说 重新下载作业后再点一次提取即可同步。

不使用提取时，也可以在电脑上用 adb 直接拷出数据再手动复制到手机：
```bash
adb pull /storage/emulated/0/Android/data/com.ets100.secondary/files/Download/ETS_secondary/resource ./ETS_data
```

扫描器与目录布局解耦：任何深度下包含 `content.json` 的 `content_*` 目录、
包含 `paper.Jason` 的套题目录都会被识别，因此 Mumu 模拟器共享目录、
未来版本改目录名也能兼容。

## 支持的题型（structure_type）

| collector | 说明 | 答案来源 |
| --- | --- | --- |
| `collector.word` | 单词跟读 | `value` + `translate` |
| `collector.read` | 朗读短文 | 原文 + `videotime` 逐句时间轴 |
| `collector.3q5a` | 三问五答 | `answer` + `std[]` + `keywords` 评分关键词 |
| `collector.picture` | 看图说话 | `std[]` 范文 + `keypoint` 要点 |
| `collector.repeat_dialogue` | 对话跟读（同步课文） | `sublist[]` 逐句原文/翻译/角色/时间轴 |
| 未知 | 通用渲染 + AI 自适应识别 | AI |

新增题型时在 `lib/models/ets_models.dart` 的 `EtsStructure` 注册，
在 `lib/pages/detail/typed_views.dart` 增加分支即可；未注册的题型自动落入通用渲染。

## AI 配置

设置页填入任意 OpenAI 兼容接口即可：

- Base URL 例：`https://api.deepseek.com/v1`
- API Key
- 模型 例：`deepseek-chat` / `glm-4-flash` / `kimi-k2`

## 构建与出包

**固定流程：双击 `tools\build\build_release.bat`**，依次完成
静态检查 → 单元测试 → Windows 构建 → 便携版打包 → 开发者版展开 → 安装包生成 → 安卓 APK，
产物自动归档：

```
产物\Windows\安装版\        E听说助手-Setup-<版本>-x64.exe
产物\Windows\绿色便携版\    E听说助手-<版本>-绿色便携版.zip
产物\Windows\开发者使用版\  E听说助手-<版本>-开发者版\   （已展开，免解压）
产物\安卓\                    E听说助手-<版本>.apk
```

单独构建：`flutter build windows --release` / `flutter build apk --release`。
架构与目录说明见 `docs/ARCHITECTURE.md`。


## 已知环境备注（本机已配置好，换机时参照）

1. Windows 需开启开发者模式（symlink 权限）。
2. 国内网络：`PUB_HOSTED_URL=https://pub.flutter-io.cn`、
   `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`；
   Gradle 走 `~/.gradle/init.gradle` 里的阿里云 Maven 镜像。
3. pub 缓存偶发不完整包（空目录），删除对应包目录重新 `pub get` 即可。
4. 若插件硬编码的 compileSdk 低于 36，会触发
   `requires ... version 36` AAR 校验错误，按 README 提示把对应插件
   `android/build.gradle(.kts)` 里的 `compileSdk` 手动改为 36。
5. Kotlin 增量编译在跨盘符路径会崩，工程已设 `kotlin.incremental=false`。
6. VS2026 对 `<experimental/coroutine>` 报错、GBK 代码页对 UTF-8 源码报 C4819，
   均已在 `windows/CMakeLists.txt` 全局处理。

## GitHub 上传清单

仓库：<https://github.com/KLP-KULIPA-24>（开源）。以下按「入仓」与「走 Releases」两处分开。

### 入仓（源码 + 展示页）

| 上传 | 说明 |
| --- | --- |
| `lib/` `test/` | 全部 Dart 源码与测试（62 个测试） |
| `android/` `windows/` | 双端工程（**签名文件已被 .gitignore 排除**，见下方） |
| `assets/` `pubspec.yaml` `pubspec.lock` `analysis_options.yaml` | 资源与依赖锁定 |
| `tools/` `docs/` | 构建脚本、设计规范（`docs/style-pack/`）与架构文档 |
| `web/docs/` | 项目主页（Pages 发布的就是它）：`index.html`、`version.json`（App「检查更新」读的版本号）、`media/`（宣传视频与海报）、`assets/`、`vendor/` |
| `web/docs/` | 项目主页（Pages 发布的源，仓库里对应 `docs/`）：`index.html`、`version.json`、`media/`、`assets/`、`vendor/` |
| `README.md` `CHANGELOG.md` `LICENSE` | 说明、**发行说明**与许可证（MIT，`Copyright (c) 2026 苦力怕.KULIPA`） |

> `web/promo/`（宣传片制作页）与 `web/README.md` 不入仓、不上传——**已弃用**，需要时从历史提交或本地备份取。

> 用网页拖拽上传时 `.gitignore` **不会生效**，务必别把 `android/key.properties`、`android/app/*.jks`
> 和 `build/`、`产物/`、`TX.png` 一起拖进去；用 `git init` + push 则自动按 `.gitignore` 排除。

**绝不入仓**（已在 `.gitignore`）：

- `android/key.properties`、`android/app/*.jks`——**APK 签名密钥与密码，泄露等于任何人都能伪造你的签名**；
- `android/local.properties`——本机 SDK 路径；
- `build/`、`.dart_tool/`、`产物/`——构建产物；
- `TX.png`（3MB 头像原图，压缩版已在 `assets/`）、`docs/next-session-prompt.md`（内部提示词）；
- `tools/remotion-promo/`、`tools/promo-reel/`（**视频制作产线**：含 node_modules 与第三方引擎副本，
  体积大、含他方许可代码，**不入仓**；仅本机出片用）；
- 仓库外的 `抓包数据/`、`ETSToolbox-main/`（真实抓包样本与逆向工具，**不要上传**，含他人数据）。

### 走 GitHub Releases（安装包不入仓，仓库只放源码）

先本地出包（`powershell -File tools/build/build_release.ps1`），再把下列文件拖进 Releases 页面：

- `产物\Windows\安装版\E听说助手-<版本>-x64.exe`
- `产物\Windows\绿色便携版\E听说助手-<版本>-绿色便携版.zip`
- `产物\安卓\E听说助手-<版本>.apk`

（`产物\Windows\开发者使用版\` 是已展开目录，仅本机调试用，不上传。）

### 展示页上线（GitHub Pages）

本地网页在 `web/docs/`，**仓库里发布的是根目录 `docs/`**（Pages 的源），更新时把 `web/docs/` 的内容同步过去
（保持 `index.html` 与 `media/`、`assets/`、`vendor/` 的相对层级——`index.html` 引用的是 `./media/E听说宣传视频.mp4` 等相对路径）：

- 仓库 Settings → Pages → Source 选 `main` 分支 + `/docs` 目录；
- 改完网页：`cp -r web/docs/. docs/`（会把 `index.html` 一起更新，设计文档仍留在 `docs/`）→ 提交。

保存后等 1~2 分钟生效。

### 版本号（App「检查更新」的取值来源）

App 启动时会（设置 → 关于 里可关）请求官网读取版本号，与本地 `kAppVersion`
（`lib/services/settings_service.dart`，当前 `0.8`）比对：

1. 优先读 `https://klp-kulipa-24.github.io/ETS-TOOLS/version.json`——**发版时改这一个文件最省事**；
2. 取不到就回退：抓官网首页，读 `class="nav-ver"` / `class="foot-ver"` 里的 `V0.8`。

所以发新版本时三处一起改：`docs/version.json` 的 `version`、`docs/index.html` 的 `V0.8`（nav-ver / foot-ver）、
App 里的 `kAppVersion`。比较按整数逐段（`0.10 > 0.9`），`0.8` 与 `0.8.0` 视为同一版本；
App 只请求 `https://klp-kulipa-24.github.io` 这一个主机。

## 免责声明

AI 输出仅供参考。
