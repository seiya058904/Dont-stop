# M7 证据索引

工程候选基于 M6 `6e3219c`，产品/回归首批提交 `1623dd2`。此目录保留诊断过程，不能把每一个历史日志都当作最终通过结果。

- `final-regression/regression-index.json`：55 个进程、4033 项断言、0 失败；旧规则断言按新产品合同更新，未删测试。12 个进程记录的退出对象严格匹配 M6 已分类的 AudioStreamMP3 / AudioStreamPlaybackMP3 与 Cephalopod.mp3，不接受任意资源错误。
- `gpu-cleanup.txt`、`regression-artifacts/gpu-cleanup.json`：原生 Vulkan，24 项/12 回营通过，敌人/临时/孤立节点全部为 0。GPU 历史残留本轮未复现。
- `shop-final.txt`、`shop-weapon.png`、`shop-attachment.png`、`shop-magazine.png`：最终标签的原生离屏渲染。170 项实际 UI 交易/选择/布局断言通过。410×230 逻辑视口对应项目像素伸缩，在 1366×768 输出截图；不是重画 UI。
- `visual-verified-tier-1.png` 至 `visual-verified-tier-5.png`：实际 R2 场景、实枪与危险圈，固定测试相机离屏渲染；五档均逐图检查。反映局部枪口、尾迹、命中与危险圈共存，不能证明完整音效、动态审美或真人舒适度。
- `tier-measured.json`、`weapons.csv`、`tier-audit.md`：最终 24 枪实测；列明有限窗口、在途结算、爆发、射程/机制及局限。
- `audit-{basic,middle,late}.json`、对应 `execution.json`：三个真实引擎进程共 90 场，运行过程中产品源文件哈希未变；`encounters-90.csv`、`difficulty-audit.md` 与 M6 对照并分离入伤系数和武器输出变化。
- `benchmark-index.json`：同一隔离副本交替还原 M6/M7 产品源码、相同压力夹具；CPU headless 与原生 OpenGL 离屏压力分别记录。结论须结合后续性能诊断，不能只选择最快样本。

## 诊断与无效样本

目录根部 `regression-*.txt` 是首次兼容回归，包含旧金币/弹药/伤害预期失败；最终结果只读取 `final-regression/`。`contracts-first` 的配件定义键误记为 4（真实 ID 9）已修正；`contracts-second` 和最终矩阵均通过。

`tier-first` 的训练目标重置 HP 污染测量；`tier-second` 的输入未送到 SubViewport；`tier-third` 为调整前数值；`tier-final` 使用标称窗口。以上均不能代替 `tier-measured`。

`visual-tier-*`、`visual-scene-tier-*`、`visual-final-tier-*` 的测试相机/枪口定位不正确，不用于证明最终画面。修正的是离屏夹具，游戏相机未改。唯一最终 Tier 截图前缀为 `visual-verified-tier-`。

无浏览器导出构建、无前台 computer use、无系统键鼠注入。原生后台渲染用于该 Godot 项目的工程检查；人类验收保持未完成。

日志归档仅规范化行尾空白和末尾空行，所有诊断与数值保留。最终拾取缓存优化后的两项相关回归见post-optimization-index.json；性能以performance.md及optimized-performance完整对照为准。
