# E听说助手

一个本地优先的 **E听说（讯飞英语听说）作业助手**，支持 **Windows** 与 **Android**。
直接解析 E听说客户端已下载到本地的作业数据，无需登录、不上传任何数据；
AI 功能仅在用户自行配置接口后由用户主动触发。仅供学习研究使用。

**作者：苦力怕.KULIPA** · [GitHub @KLP-KULIPA-24](https://github.com/KLP-KULIPA-24)

## 功能总览

| 功能 | 说明 |
| --- | --- |
| 作业列表 | 递归扫描 ETS 数据目录，按"文件夹名（数字）- 标题 - 类别"收纳，同类多条折叠为文件夹；单词组进入单词本页（可隐藏释义自测） |
| 答案查看 | 五种题型专属渲染：模仿朗读 / 角色扮演 / 故事复述 / 对话跟读 / 单词跟读；背题模式一键隐藏全部答案 |
| 标题三级策略 | ① 模板提取（paper.Jason `tz_mc`、`topic`、`read_title`）→ ② 自适应匹配 → ③ AI 智能匹配 |
| 精听播放 | 倍速 0.6x–2.0x、A-B 循环；逐句按 `begintime~endtime` 区间播放 |
| 多提供商 AI | 任意 OpenAI 兼容接口；每个提供商可配多个模型；模型支持**思考档位**（Agnes 出厂只有关/开，其他模型默认低/中/高，可自定义到超高/最高）与**多模态（图片输入）**；流式输出 |
| AI 实时对话 | 详情页"AI 对话"入口，多轮流式对话，可附图片，历史持久化 |
| AI 智能排版 | 智能解析 / 全文翻译 / AI 标题 / 未知题型 AI 自适应识别，结果缓存 |
| 模拟考场 | 按 ctrl 流程复现考试：播放→倒计时→录音→回放，支持中途跳过 |
| Android 悬浮窗 | 折叠为圆形 Logo，点击展开：答案速览 / 播放控制 / AI 实时快问（仅安卓；Windows 端已下线该功能，用窗口置顶/托盘代替） |
| 修改栏 | 本地拦截引擎接管作业提交：PAC（仅拦截 E听说 域名，Windows）/ 全流量（安卓）两种接入模式，按规则改写**成绩**与**完成时间**；HTTPS 证书一键安装，数据不出本机 |
| 软件风格 | 默认 Material 3 风格 / **iOS 26 玻璃模糊风格**一键切换；主题色板 + 色相滑条自定义颜色；深浅色 |

## 数据目录

应用自动扫描以下位置（可在"设置"中追加）：

- **Windows**：`%APPDATA%\ETS`（即 `C:\Users\<用户>\AppData\Roaming\ETS`）
- **Android**：`/storage/emulated/0/Android/data/com.ets100.secondary/files/Download/ETS_secondary/resource`
  （需要授予"所有文件访问"权限）

### Android 11+ 读不了 Android/data？（重要）

Android 11+ 限制读取**其他应用**的 `Android/data` 目录，即使授予"所有文件访问"也不行。
APP 内置四种提取通道（设置 → 数据目录 →「选择工作授权模式」，勾选已就绪的通道 →「用 X 开始提取」）：

| 通道 | 适用 | 步骤 |
| --- | --- | --- |
| **Shizuku** | 免 root 真机（最稳） | 安装 Shizuku → 开发者选项打开无线调试 → Shizuku 配对启动 → 回本 APP 点授权 → 开始提取 |
| **Root**（libsu） | Mumu 模拟器、已 root 真机 | Mumu 设置 → 其他设置 → 开启 ROOT，回本 APP 直接选 Root 提取 |
| **直读**（零提权） | 部分机型 / 模拟器可直接读 `Android/data` | 无需授权，选中即提取 |
| **SAF**（系统授权） | 系统文件选择器兜底 | 点右侧按钮选择 E听说 的 `resource` 目录授予访问，再提取 |

提取会把 E听说 数据拷贝到本应用私有目录（`Android/data/com.eets.e_ets_helper/files/ets_data`），
之后扫描、精听、安卓悬浮窗全部正常；每次 E听说 重新下载作业后，回作业页点一次「刷新」即可同步。

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
| `collector.read` | 模仿朗读 | 原文 + `videotime` 逐句时间轴 |
| `collector.3q5a` | 角色扮演 | `answer` + `std[]` + `keywords` 评分关键词 |
| `collector.picture` | 故事复述 | `std[]` 范文 + `keypoint` 要点 |
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
| `docs/` | **网页源 + Pages 发布目录**：`index.html`、`version.json`、`media/`（宣传视频与海报）、`assets/`、`vendor/`，以及设计文档（`ARCHITECTURE.md`、`style-pack/`） |
| `README.md` `CHANGELOG.md` `LICENSE` `发行日志/` | 说明、发行说明、许可证（MIT）与每个版本的 Release 正文 |

> `web/promo/`、`web/README.md` 不入仓、不上传——**已弃用**；`web/docs/` 也不入仓（本机历史拷贝，仓库 `docs/` 才是网页源）。

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

**网页源就是仓库根目录 `docs/`**（Pages 的源），直接改这里提交即可；保持 `index.html` 与 `media/`、`assets/`、
`vendor/` 的相对层级——`index.html` 里引用的是 `./media/E听说宣传视频.mp4` 等相对路径。

- 仓库 Settings → Pages → Source 选 `main` 分支 + `/docs` 目录，保存后过 1~2 分钟生效；
- 本机 `web/docs/` 是历史遗留的另一份拷贝（**不入仓、已进 .gitignore**）：以后改网页只改仓库 `docs/`，
  或者改完手动 `cp -r web/docs/. docs/` 同步，别再让两份各自漂移。

### 版本号（App「检查更新」的取值来源）

App 启动时会（设置 → 关于 里可关）请求官网读取版本号，与本地 `kAppVersion`
（`lib/services/settings_service.dart`，当前 `0.8.1`）比对：

1. 优先读 `https://klp-kulipa-24.github.io/ETS-TOOLS/version.json`——**发版时改这一个文件最省事**；
2. 取不到就回退：抓官网首页，读 `class="nav-ver"` / `class="foot-ver"` 里的 `V0.8.1`。

所以**发新版本时要一起改这五处**：`pubspec.yaml` 的 `version:`、`lib/services/settings_service.dart` 的 `kAppVersion`、
`windows/installer.iss` 的 `MyAppVersion`、`docs/version.json` 的 `version`、`docs/index.html` 的 `V0.8.x`（nav-ver / foot-ver）。
比较按整数逐段（`0.10 > 0.9`），`0.8` 与 `0.8.0` 视为同一版本。

App 只请求两个白名单主机：主站 `https://klp-kulipa-24.github.io/ETS-TOOLS/` 与
备用站 `https://ets-tools.klp-kulipa.workers.dev/`（内容与主站一致）——**主站连不上就自动改问备用站**
（国内访问不了 GitHub Pages 时不至于查不到更新）。改版时**两个站的内容都要更新**（备用站是独立的一份静态副本，不是实时反代）。

### 下载渠道与制品名

网页与 App 都按四个渠道给下载入口：**蓝奏云**（提取码 `ets`）/ **银盘** / **GitHub 解析下载**（前缀见下）/ **GitHub 原版下载**。
出包脚本的产物名与 Release 资产名一致（`ETS-TOOLS-Setup-<版本>-x64.exe` / `ETS-TOOLS-<版本>-win.zip` /
`ETS-TOOLS-Android-<版本>.apk`），**拖进 Release 不用再手动改名**。

网页里的 GitHub 直链写在 `docs/index.html` 的 `REL_BASE`（当前 `…/releases/download/V0.8.1/`），
**发新版时改这一处**，并保证资产名与上面格式一致、tag 用 `V<版本>`（如 `V0.8.1`）。
网盘（蓝奏云 / 银盘）那六条链接写在同一文件的 `DL_CHANS` 里，换文件重传后要同步更新。
加速解析前缀在网页 `docs/index.html` 的 `MIRROR` 与 App 的 `kShizukuMirrorUrl` 两处，需保持一致。

## 免责声明

AI 输出仅供参考。
