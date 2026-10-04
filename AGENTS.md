# Don't Stop：项目与验证指南

## 工作区与权威入口

- Git 根是本目录；Godot 项目是 `Don't stop/project.godot`，不是外层目录。命令中的项目路径必须整体引用，避免空格和英文撇号被 shell 拆分。
- `boot/Boot.tscn` 是配置入口，加载 `game/map/Main.tscn`；Web 启动界面由 `web/loader.html` 提供。以上路径均相对于 Godot 项目目录。
- 项目内 `autoload/` 管理全局状态，`game/` 包含玩法与配置，`ui/` 包含界面，`Sprites/`、`audio/`、`fonts/`、`shader/` 与 `addons/` 是产品资源。`tests/` 是原生回归场景，`tools/` 是导出、浏览器与证据校验工具。
- 根 README 提供正式下载与试玩入口；正式版本来自相应 tag，当前 `main` 可以包含后续维护。`Don't stop/docs/iteration/` 保留历史设计与审计证据，不能把旧报告的状态、SHA 或命令当作当前工程配置。

## 运行与验证

使用 CI 固定的 Godot 4.7.2 及匹配的导出模板、Python 3、Node.js；浏览器验证使用 Playwright/Chromium，版本以 `.github/workflows/deploy-pages.yml` 为准。以下是从 Git 根运行的 Bash 命令，`GODOT` 指向实际引擎可执行文件；Windows 使用等价参数并等待引擎进程结束。

```bash
"$GODOT" --path "Don't stop"
"$GODOT" --headless --path "Don't stop" --editor --import --quit --log-file "$PWD/import.log"
python "Don't stop/tools/b194_import_check.py" "Don't stop" import.log
"$GODOT" --headless --path "Don't stop" --quit-after 60000 res://tests/B194Contracts.tscn
"$GODOT" --headless --path "Don't stop" --quit-after 60000 res://tests/P0SaveSanity.tscn
"$GODOT" --headless --path "Don't stop" --quit-after 60000 res://tests/BaselineRegression.tscn
node "Don't stop/tools/stress-completion.test.js"
```

按改动选择额外场景，以当前 CI 中的调用为准。新缓存的首次导入可能先报告字体/光标尚未导入；只有导入校验器确认资源已生成，且后续 B194Contracts 通过，才能接受这些特定早期诊断。其他脚本错误或失败断言不能忽略。

导出预设名必须精确匹配 `Don't stop/export_presets.cfg`；输出路径相对于项目目录：

```bash
mkdir -p "Don't stop/build/web" "Don't stop/build/windows"
"$GODOT" --headless --path "Don't stop" --export-release "Web Release" build/web/index.html
"$GODOT" --headless --path "Don't stop" --export-release "Windows x64 Release" "build/windows/Don't stop.exe"
python -m http.server 8788 --bind 127.0.0.1 --directory "Don't stop/build/web"
# 另开终端，确保 Node 能解析已安装的 playwright；浏览器证据保持在被忽略目录。
mkdir -p output
node "Don't stop/tools/smoke-web.js" http://127.0.0.1:8788/index.html output
```

`Don't stop/PLAY_GAME.bat` 会导出并启动 Windows 源码版本，依赖项目内 `README-PLAY.md` 指定的工作区便携工具；`Don't stop/PLAY_WEB.bat` 只服务已有 `build/web`，不会自动导出。不要删除这些入口依赖。

## 必须保留的约束

- 保持玩法、数值、RNG 序列及存档兼容性。开发存档目录为 `TowDownGame-Iteration`，`public_release` 使用 `TowDownGame`；测试须隔离用户数据，不能覆盖真实存档。
- Web 保存只有 IndexedDB 提交并确认指定快照后才能报告成功；失败保持 dirty 状态与重试/导出能力。不得把仅写入 MEMFS 或调用文件同步当作持久化成功。
- SceneManager 的转场图案有动态路径；保留 Boot 中的资源引用与导出 include filter。不要因未出现静态调用而删除资源。
- `.godot/`、`build/`、本地输出、Python 字节码和浏览器缓存可再生成；正式资源、`.import` 源资源描述、已提交审计证据与历史原件不能据此删除。根 `archive/` 是忽略的本地历史/工具存储，部分内容仍是启动依赖。
- `deploy-pages.yml` 在 main 推送时按范围构建、验证并部署同一 Web 产物；仅文档变更会跳过游戏部署，线上构建 SHA 因此可以保持为上次部署的提交。`native-tests.yml` 是手动/月度/Release 完整验收，`build-windows.yml` 是 Windows 打包流程。不要为普通文档维护触发长跑或新 Release。
- Pages 身份由提交 SHA、`index.wasm || index.pck || index.js` 的摘要及各文件哈希共同证明；使用 `tools/stamp-build-identity.py`、`tools/verify-pages-deployment.js` 的实际接口，不能仅以 HTTP 200 验收。

修改保持单目的；先检查现有工作区，完成适用回归、构建、入口 smoke 和 `git diff --check`，再审阅最终 diff。发布、tag、远端配置与历史改写必须有明确授权。
