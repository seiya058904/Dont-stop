# Don't Stop v1.3.6

本 patch 包含 v1.3.5 后已经进入主线的跨进程前驱保护与 legacy 原件归档，并修复 Web 保存失败后明确丢弃的同实例启动恢复：精确回写已提交前驱后，完成旧恢复身份，再允许正常加载。读取失败、字节不匹配、恢复记录无法确认时仍拒绝释放保护；未提交购买不得进入 IndexedDB，已提交武器必须全部保留。

Windows x64 预设 file/product version 为 1.3.6，Web/Windows 均使用 public_release 配置与原有存档目录/schema。候选 `ceabdfa` 已通过 [完整 native](https://github.com/seiya058904/Dont-stop/actions/runs/38217635282)、[完整 Web](https://github.com/seiya058904/Dont-stop/actions/runs/38217631713) 与 [Windows 构建](https://github.com/seiya058904/Dont-stop/actions/runs/38217638545)。正式主线的部署、包身份和上传下载哈希仍以 Release provenance 为准，不从本文推断资产已经发布。

完整门禁保持 65 active native 调用（v1.3.5 的 64 个原参数调用加 R1RecoveryJournal），并保持 durable 的所有真实 abort、quota、reload、18 秒上限、旧确认与恢复事务断言。新增 Web 断言检查硬超时丢弃后武器 0/3/4 全部保留且恢复锁解除，不以快速 Pages 门禁代替完整 durable。

发布 provenance 应列出实际 commit、Actions run、once-exported Web identity、Windows/Web ZIP 与 SHA-256。旧 Release/tag/资产和本次失败日志保留。浏览器页面关闭/刷新及 IndexedDB 故障测试与物理断电、操作系统强杀不等价；后两者未执行时明确登记。Stage40 历史峰值风险继续按原有复现与性能契约观察，不放宽门限。
