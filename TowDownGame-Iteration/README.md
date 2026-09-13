# TowDownGame Iteration

当前唯一公开的 TowDownGame 迭代项目，使用 Godot 4。源码、资源、测试、工具和正式迭代文档均保留在本目录内；本次整理不删除游戏内容。

## 启动

双击 [`PLAY_GAME.bat`](PLAY_GAME.bat) 启动试玩。它依赖工作区本地保留的 Godot 4.7.2 portable runtime，不是独立发行包。详细操作见 [`README-PLAY.md`](README-PLAY.md)。

## 目录职责

- `game/`、`ui/`、`autoload/`、`audio/`、`Sprites/`、`shader/`：游戏运行时源码和资源。
- `tests/`、`tools/`：回归夹具、验证脚本和报告工具。
- `docs/iteration/`：M0—M12 迭代记录、正式证据和验收状态。
- `project.godot`、`PLAY_GAME.bat`、`export_presets.cfg`：工程与本地启动配置。

`.godot/`、日志、临时文件以及本地导出目录属于机器生成物，由 `.gitignore` 排除；正式源码、测试、文档和证据不因本次整理删除。

当前状态：**M12 CLOSED / HUMAN ACCEPTED WITH KNOWN LIMITATIONS**。不进入 M13；接受记录和限制见 [`docs/iteration/STATUS.md`](docs/iteration/STATUS.md)。
