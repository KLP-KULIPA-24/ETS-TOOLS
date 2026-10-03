# 发行日志

每个对外版本一个 Markdown 文件（如 `V0.8.md`），内容是**可以直接粘到 GitHub Release 正文**的发行说明。

规则：

- 对外的版本号按 `0.8.1` / `0.8.2` … 递增，`pubspec.yaml` 的构建号（`0.8.x+N`）继续递增用于覆盖安装——
  改版本号时同步五处：`pubspec.yaml`、`lib/services/settings_service.dart` 的 `kAppVersion`、
  `windows/installer.iss` 的 `MyAppVersion`、`docs/version.json`、`docs/index.html` 的 `V0.8.x`（nav-ver / foot-ver）。
- 出包后把 `产物/` 里的三个安装包（`ETS-TOOLS-Setup-*.exe` / `ETS-TOOLS-*-win.zip` / `ETS-TOOLS-Android-*.apk`）
  拖进 GitHub Release 附件——名字已经和网页直链一致，不用改；tag 用 `V<版本>`（如 `V0.8.1`），
  然后在网页 `docs/index.html` 里同步 `REL_BASE`（GitHub 直链前缀）与 `DL_CHANS` 里的网盘链接。
- `CHANGELOG.md` 是给仓库看的总账，本目录是给「每个 Release 页面」看的单版本说明，两者内容可以重叠。
