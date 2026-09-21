# Don't Stop

这是当前唯一公开的 Don't Stop 游戏工程，使用 Godot 4.7.2。源码、运行时资源、测试、工具和正式迭代文档都保留在本目录内。

## 公开试玩与发布状态

GitHub Pages 浏览器版是当前主要公开试玩入口：<https://seiya058904.github.io/Dont-stop/>。

Windows x64 仍支持本地开发和构建，但当前不发布新的 GitHub Windows Release；已有历史 Release 不在本轮修改。

## 启动

双击 [`PLAY_GAME.bat`](PLAY_GAME.bat) 启动本地试玩。它依赖工作区内的 Godot 4.7.2 portable runtime，不是独立发行包。详细操作见 [`README-PLAY.md`](README-PLAY.md)。

## 目录职责

- `game/`、`ui/`、`autoload/`、`audio/`、`Sprites/`、`shader/`：游戏运行时源码和资源。
- `tests/`、`tools/`：回归夹具、验证脚本和报告工具。
- `docs/iteration/`：B12–B19.3 及更早迭代的报告、结论和保留证据。
- `project.godot`、`PLAY_GAME.bat`、`export_presets.cfg`：工程与本地启动配置。

`.godot/`、日志、临时文件以及本地导出目录属于机器生成物，由 ignore 规则排除；正式源码、测试和报告不因本轮整理删除。
