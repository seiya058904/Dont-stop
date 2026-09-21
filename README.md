# Don't Stop

[Play in Browser](https://seiya058904.github.io/Dont-stop/)

GitHub Pages 是当前主要的公开试玩入口。Windows x64 仍支持本地和开发构建，但当前不发布新的 GitHub Windows Release；已有 v1.0.0、v1.0.1、v1.0.2 仅作为历史发行记录保留。

Don't Stop 是一款俯视角 2D 生存射击游戏：移动、瞄准、射击、换弹与冲刺，完成遭遇后回到营地购买武器和永久强化。

## 当前状态

当前开发记录已经经过 B12–B19.3。本轮目标是恢复 CI 正确性、暂停自动 Windows Release、整理仓库证据与公开说明；不新增玩法、不改平衡，也不重写 Git 历史。

自动化通过与真人验收分开记录；现有迭代文档中的 `HUMAN_ACCEPTED` 状态不会因 CI 变绿而自动改变。

## 本地试玩

- Windows 源码试玩：运行 [`Don't Stop/PLAY_GAME.bat`](Don't%20stop/PLAY_GAME.bat)，需要工作区保留的 Godot 4.7.2 portable runtime。
- 本地 Web 候选：运行 [`Don't Stop/PLAY_WEB.bat`](Don't%20stop/PLAY_WEB.bat)，服务 `Don't Stop/build/web/`。
- 本地 Windows 构建：运行 `Don't Stop/build/windows/Don't Stop.exe`，并保留同目录的 `Don't Stop.pck`。

这些路径是开发/验证入口，不代表新的稳定 Release 已发布。

## 仓库结构

- [`Don't Stop/`](Don't%20stop/)：当前游戏源码、运行时资源、测试、工具和迭代文档。
- [`Don't Stop/docs/iteration/`](Don't%20stop/docs/iteration/)：正式报告、历史结论和少量可复核证据。
- `archive/`：本地归档与支持运行时，不上传云端。

详细操作见 [`Don't Stop/README-PLAY.md`](Don't%20stop/README-PLAY.md)；历史迭代继续保留在 `Don't Stop/docs/iteration/`，不在根 README 重复展开。
