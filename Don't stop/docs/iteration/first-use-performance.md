# 首次射击与冲刺性能修复

基线：`codex/visual-gilding` / `15b9175`（Final Visual Polish）。保留透明 HUD、现有美术、玩法数值、存档格式与命中规则。

## 复现与原因

使用全新 Chromium 会话与存储，通过真实鼠标 / 键盘购买并装备 Boom Boi，在营地第一次射击。只读 probe 确认弹药消耗；浏览器 RAF、Long Tasks 与单独的 CDP trace 记录时间，不通过平均 FPS 掩盖长帧。

RX 7900 XT / ANGLE D3D11 上，首次射击连续产生约 1452 / 1462 ms 两个主线程长任务。trace 中四次 `GLES2Implementation::GetProgramiv` 等待各约 690–703 ms；第二、第三发恢复正常。首次冲刺另有约 1381 ms 长任务。资源已预载，阻塞发生在首次使用 GPU 程序的编译 / 链接等待，并非磁盘读取或激光命中逻辑。

## 最终改动

- Boom Boi 两套 50 / 24 粒子的短生命周期效果、角色 50 粒子的冲刺效果改用 CPU 粒子。保留原始纹理、曲线、颜色、寿命、发射参数与 30 Hz 模拟频率，避免这些小效果单独触发昂贵 GPU 模拟程序。
- 删除激光每发创建的旧版重复枪口粒子，复用现有 `TierMuzzle`；保留被移除节点在 Godot 4.7.2 中消耗的随机数，避免影响后续暴击 / 敌人选择。
- 激光空闲时不再更新射线与不可见几何；活动时显式查询一次，关闭原有重复的自动 RayCast 查询。伤害 tick、射程、弹药、墙体判定及淡出时间保持不变。
- `LightweightParticles.gd` 补齐 GPU → CPU 节点转换的随机数消耗差异；Windows 预热兼容两种粒子节点。没有增加 Web 启动预热或把长卡顿挪到加载界面。
- 试验过公共命中烟尘转换，未测得明确收益，因此回退该候选，不扩大最终修改范围。

涉及产品文件：`game/guns/BoomBoi.gd/.tscn`、`game/hero/Hero.tscn`、`game/effects/LightweightParticles.gd`、`autoload/Warmup.gd`。专项回归在 `tests/BeamPerformance.*`、`tests/M9Beam.gd`、`tools/web-first-shot.js`。

## 验证方法与边界

| 本机实测 | 修改前 | 最终包 |
| --- | ---: | ---: |
| Boom Boi 首发最大 RAF 间隔 | 1466.6 ms | 33.4 ms |
| 第二 / 第三发最大 RAF 间隔 | 16.8 ms | 16.8 ms |
| 首次冲刺最大 RAF 间隔 | 1366.7 ms | 16.8 ms |
| 首发 / 冲刺超过 50 ms 的浏览器长任务 | 3 | 0 |
| Stage 39 / D，复测平均帧间隔 | 16.66 ms | 16.66 ms |
| 同场景 P95 / P99 | 18.70 / 20.60 ms | 18.70 / 21.00 ms |
| 同场景峰值 / 超过 50 ms 帧数 | 36.70 ms / 0 | 39.00 ms / 0 |

改善集中在首次使用停顿，持续战斗没有宣称获得额外 FPS。正式最终包数据：`delivery-cold-6/result.json`、`delivery-dense-repeat/stress-after-repeat-D.json`；对照：`cold-before/result.json`、`dense-before-repeat/stress-before-repeat-D.json`。

| 回归 | 结果 |
| --- | --- |
| BeamPerformance，headless / 原生渲染 | 13 / 13，各全部通过 |
| M9Beam | 312 / 312 |
| PresentationContracts / PresentationRng / PresentationLifecycle | 55 / 8 / 52，各全部通过 |
| Web 真实输入购买、装备、三次射击、冲刺、出战、移动和装填 | 通过，冷路径 100 ms 门限通过 |
| 原生激光开放空间 / 墙体前后截图 | 通过，命中与视觉端点一致 |
| Windows 完整 EXE，13 类武器冷路径 / 连续战斗 | 完成；Boom Boi 首发最大 6.3 ms，连续战斗 P95 6.7 ms |
| Windows 独立包标准 smoke | `result=PASS`，退出码 0 |
| Web / Windows Release 导出，Git diff 检查 | 通过 |

每次冷启动均新建浏览器进程及独立存储。正式计时期间不截图；射击和冲刺计时结束后再截图、进入正常战斗、移动、射击与装填。`MAX_FRAME_MS=100` 为本机冷路径回归门限，不能解释为所有硬件的保证。

原生前后截图同时检查无墙激光与墙体阻挡，保持光束及末端火花表现。`M9Beam` 检查 100–1050 px、墙体、旋转、缩放及相机变换；原有测试把武器移到独立坐标后未更新后坐力锚点，950 px 用例在原版也失败，现修正测试锚点，未修改游戏射程。

工程检查覆盖 RNG、反复射击的节点数量、切枪 / 装填取消、残留异步回调、表现契约及 10 次战斗 / 回营生命周期。存档操作使用隔离测试环境。

普通弹丸在营地首次发射仍测得约 250 ms 的其他 Canvas 程序首次使用抖动，本轮不宣称清除了所有武器 / 驱动的首次编译成本。持续战斗以相同的 Stage 39 / D 场景、30 秒、180 敌人上限作对比，性能结果不能外推到全部硬件或长时间耐久测试。

一次最终包 D 压测完成并回主菜单后出现 `ObjectDB::get_instance: slot >= slot_max` 引擎诊断；同包重新完整运行未复现，画面和菜单恢复正常。保留失败与复测日志，不将其写成已修复或证明属于旧版；未在此性能补丁中猜测性修改场景 / 存档生命周期。

Windows `--smoke --stutter` 直接退出时有纹理 RID / ObjectDB 清理诊断；对旧版完整 EXE 运行相同测试复现相同诊断。最终包标准 smoke 返回 PASS / 0，退出时仍有 ObjectDB 清理警告。它们不等于战斗中持续泄漏（10 轮生命周期检查通过），也没有被掩盖为零告警。

原始日志、帧数据、trace、截图位于本地 `output/performance/`；不打入游戏包。

## 本地交付

- Web：`build/performance/index.html`，完整同目录资源；本地地址 `http://127.0.0.1:8765/performance/index.html`。
- Windows：`build/performance-windows/Don't Stop.exe` 及同目录 PCK。
- 便携包：`build/Dont-Stop-Performance-Windows.zip`。
- 文件校验及提交身份：`build/performance-manifest.json`。未推送、合并或远程发布。
