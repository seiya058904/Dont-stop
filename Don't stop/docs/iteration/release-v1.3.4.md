# Don't Stop v1.3.4

本版只修复 v1.3.3 的 Web 返回主菜单保存提示闪现。产品修复基于 `ee1c90174d3e12253f48cfc826261044fc55154d`；最终 main、Actions、正式 ZIP 哈希与 Pages payload identity 以 [v1.3.4 Release](https://github.com/seiya058904/Dont-stop/releases/tag/v1.3.4) 的 provenance 为准。旧 tag、资产及历史失败证据保持原样。

## 离开与持久化

CAMP 当前 snapshot 与已 durable 快照一致时直接返回，不重新提交或新增 revision。相同 snapshot 已提交、只等 IndexedDB 确认时复用现有请求；有真实新变化时正常保存。两条 pending 路径均静默等待，保留 dirty/beforeunload 保护并暂停输入；确认后再次核对当前 snapshot，成功才离开。失败/超时、blocked/corrupt recovery 与不能安全保存的战斗离开继续显示完整保护选项。JSON 数字表示归一化只用于判断状态是否变化，IndexedDB 仍确认精确提交字节。

DS-001 的新档恢复事务、坏档原文、discard、retry、存档 schema 和目录保持不变。无延迟隐藏 Dialog，无美术、玩法、数值或性能改动。

## 验证与证据

局部候选完成 8 个相关 native 场景的 171 条断言、Web durable/DS-001 的 70 条检查、20 轮 menu-return soak 与额外重开、save audit、smoke、loader 和本地 Web 身份校验。新增断言覆盖无变化不写入、pending 不闪、旧确认无效、等待中的更新不丢失、失败后保护、购买后立即返回和战斗确认。

首轮 Web 验证发现驱动在新失败 Dialog 出现前点击上一轮遗留的下载坐标；日志保留了点击早于失败确认的顺序。驱动改为等待本轮新控件，完整重跑通过；没有放宽产品超时或数据保护断言。R1RecoveryUI 退出时保留基线同样的 6 ObjectDB / 3 resources 诊断，P0SaveSanity 保留故意触发的 HP 钳制诊断，不宣称零告警。

发布要求最终 PR 头的现有云端门禁与完整 64 active native 调用通过（58 contracts、6 pressure，含原参数和自然完成标记），合并后关联最终 main 构建和实际测试的 Web bytes。正式 Web ZIP 复用经测试并部署的 Pages artifact；Windows ZIP 使用同一 main 的 headless export，资产上传后下载回验 SHA-256。

本 patch 不重做 4K、首枪或 Boss 性能调查。既有性能结论与限制继续见 [v1.3.2 审计](release-v1.3.2.md)；本次正式 Actions 完成状态和全量验收结果只以 release provenance 的具体 run/commit 为准，不把历史结果转记到新提交。
