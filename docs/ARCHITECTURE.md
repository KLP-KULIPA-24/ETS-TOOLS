# E听说助手 · 架构说明

> 内部测试版。结构按功能域组织，方便后续开源。

## 顶层结构

```
E:\EtsHelper\
├─ lib/                 # 应用代码（按域分层）
├─ test/                # 单元测试（flutter test）
├─ tool/                # 素材/图标生成脚本（Dart）与整理脚本
├─ docs/                # 文档（设计规范、演示数据、下次会话提示）
├─ windows/ android/    # 平台工程
├─ 产物/                # 出包目录（不入库）
│  ├─ Windows/
│  │  ├─ 安装版/        # Setup exe（双击装到系统，分发给他人）
│  │  ├─ 绿色便携版/    # zip（解压即用不写注册表，自用/U盘）
│  │  └─ 开发者使用版/  # 已展开的免解压目录（改完直接双击验证）
│  └─ 安卓/            # apk（装手机）
├─ tools/
│  ├─ build/            # 出包流程（build_release.bat → build_release.ps1）
│  ├─ assets/           # 素材生成脚本（图标/ico/头像/演示数据）
│  ├─ third_party/      # 第三方二进制（nuget.exe / innosetup.exe / 中文语言包）
│  └─ legacy/           # 历史一次性脚本（归档备查，不再维护）
└─ build/               # Flutter 构建缓存（不入库）
```

## 出包（每次改完的固定流程）

**只需双击 `toolsuilduild_release.bat`**，脚本按序完成七步，
任何一步失败即中止并报错：

1. `flutter analyze`（静态检查必须零问题）
2. `flutter test`（单元测试必须全过）
3. `flutter build windows --release`（先清 CMake 缓存，避免 nuget 缺失被缓存住）
4. **绿色便携版** → `产物\Windows\绿色便携版\E听说助手-<版本>-绿色便携版.zip`
5. **开发者使用版** → `产物\Windows\开发者使用版\E听说助手-<版本>-开发者版\`
   （Release 目录整份拷贝，免解压，改完可直接双击 exe 验证）
6. **Windows 安装版** → `产物\Windows\安装版\E听说助手-Setup-<版本>-x64.exe`
   （Inno Setup 编译，中文语言包在 `tools/third_party/ChineseSimplified.isl`）
7. **安卓 APK** → `产物\安卓\E听说助手-<版本>.apk`

版本号取自 `pubspec.yaml` 的 `version:` 字段，出包时自动写进文件名。

## lib/ 分层

| 目录 | 职责 |
| --- | --- |
| `lib/main.dart` | 入口：加载设置、成就、窗口/托盘初始化、MaterialApp 与主题 |
| `lib/app/` | 应用外壳：自适应导航（宽屏左栏 / 手机底部胶囊）、窗口行为 |
| `lib/models/` | 数据模型：作业条目、题型枚举、解析结构 |
| `lib/services/` | 业务服务：数据扫描、AI（流式/故障切换/限速）、设置、对话存储、成就、悬浮桥 |
| `lib/widgets/` | 通用 UI：玻璃容器、卡片、文本、颜色、AI 结果渲染 |
| `lib/pages/homework/` | 作业域：列表（筛选/搜索/视图/多选管理）、单词本、模拟考场 |
| `lib/pages/ai/` | AI 对话页（会话列表 → 聊天子界面） |
| `lib/pages/modify/` | 修改域：抓包拦截配置、成绩/完成时间规则 |
| `lib/pages/settings/` | 设置域：设置、关于、教程、成就页 |
| `lib/pages/detail/` | 作业详情域：五类题型渲染、AI 面板 |
| `lib/pages/floating/` | 悬浮窗页（Windows 悬浮模式 / Android 悬浮层） |
| `lib/overlay_main.dart` | Android 悬浮层独立入口 |

## 约定

- **相对导入**：文件移动后注意 `../` 层级；同域页面互引用平级路径。
- **字号**：只用 style-pack 规范档 12 / 13 / 14 / 18（禁止随手 10.5/11/15/16）。
- **控件高度**：按钮/输入 44；卡片圆角 16；控件胶囊形。
- **深浅色**：所有颜色走 `ColorScheme` / `StyleTokens`，禁止硬编码主题色。
- **持久化**：`SharedPreferences`（设置/成就）+ 应用 Documents（对话/缓存）；敏感 Key 走系统加密存储。
- **平台差异**：Windows 与 Android 分支显式判断（`Platform.isWindows`），共享业务逻辑。

## 构建与出包

见上文「出包（每次改完的固定流程）」小节。
唯一入口：`tools\build\build_release.bat`。
产物目录 `产物/` 与 `build/` 均不入 Git。

## 测试版 → 开源前清单

- [ ] 版本号与 CHANGELOG 对齐（pubspec `version:`）
- [ ] 移除个人化默认（演示数据路径、作者信息按需保留署名）
- [ ] 依赖许可证复核（AGPL/GPL 传染性检查）
- [ ] Issue/PR 模板与贡献指南（CONTRIBUTING.md）
