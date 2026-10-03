# 发行日志

每个对外版本一个 Markdown 文件（如 `V0.8.md`），内容是**可以直接粘到 GitHub Release 正文**的发行说明。

规则：

- 对外版本号固定 `0.8`，只递增 `pubspec.yaml` 的构建号（`0.8.0+N`，覆盖安装用）——
  改版本号时同步：`CHANGELOG.md`、本目录的版本文件、`lib/services/settings_service.dart` 的 `kAppVersion`、
  `windows/installer.iss`、以及网页的 `docs/version.json` + `docs/index.html` 的 `V0.8` 标记。
- 出包后把 `产物/` 里的三个安装包（Windows 安装版 / 绿色便携版 / 安卓 APK）拖进 GitHub Release 附件。
- `CHANGELOG.md` 是给仓库看的总账，本目录是给「每个 Release 页面」看的单版本说明，两者内容可以重叠。
