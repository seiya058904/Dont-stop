# 13 来源、定位与验证边界

本文件用于让Codex复核，不是对三个项目质量或第三方资产权利的认证。源码均以外层公开仓库快照 `e267aa449c45860c42a3d0e8ae6a26e635341ba7` 为定位；本地版本可能已有新变化。

根地址：`https://github.com/seiya058904/game-prototype-lab`
具体源码地址格式：`https://github.com/seiya058904/game-prototype-lab/blob/e267aa449c45860c42a3d0e8ae6a26e635341ba7/<path>`。路径中的空格按URL编码。

## 一、已阅读的工作区/主项目来源

| 编号 | 路径 | 支持的事实或审计入口 |
|---|---|---|
| S01 | `README.md` | 原型冻结、复制迭代、三原项目只读、工具目录、真人验证 |
| S02 | `TowDownGame/autoload/Utils.gd` | 10武器、9配件注册及工具入口；freezeFrame实际实现需复核 |
| S03 | `TowDownGame/autoload/PlayerData.gd` | 9999金币、reward_point、经验setter、全局帧切枪锁 |
| S04 | `TowDownGame/ui/widgets/ShopPanel.gd` | 枪/配件购买、choose_am残留、金币扣款 |
| S05 | `TowDownGame/ui/Inventory.gd` | 已有背包、槽位、拖拽、装卸和暂停路径 |
| S06 | `TowDownGame/autoload/server/LevelServer.gd` | 30轮表、Timer、胜利/下一轮与奖励点 |
| S07 | `TowDownGame/autoload/server/RewardServer.gd` | 12奖励注册、加层上限与发信号 |
| S08 | `TowDownGame/ui/widgets/RewardChoose.gd` | 原购买扣天赋点；金币按钮用于刷新推荐 |
| S09 | `TowDownGame/game/reward/BaseReward.gd` | only_start、max_count、onCountChange、触发回调 |
| S10 | `TowDownGame/game/guns/BaseGun.gd` | 弹匣重算、射击/装填、配件和激光共用fire |
| S11 | `TowDownGame/game/attachments/BaseAttachment.gd` | 定义ID/实例ID、兼容类型和装卸回调 |
| S12 | `TowDownGame/game/guns/BoomBoi.gd` | 射线激光、临时子弹载荷、tick和异步停止 |
| S13 | `TowDownGame/game/bullets/Bullet.gd` | 普通弹fire附加玩家伤害、运动碰撞、寿命 |
| S14 | `TowDownGame/game/monster/BaseMonster.gd` | 直接追逐、命中/死亡奖励和回调 |
| S15 | `TowDownGame/game/map/mapTown/Town.gd` | 主刷怪场景、营地/传送、死亡、回合清理 |
| S16 | `TowDownGame/ui/GameUI.gd` | 玩家HUD、奖励图标与only_start跳过、背包入口 |
| S17 | `TowDownGame/ui/widgets/RewardTopItem.gd` | 图标和数量更新，不等于完整天赋详情 |
| S18 | `TowDownGame/game/map/Main.tscn` | 主入口连接与很低环境色；不是完整迷雾复现 |
| S19 | `TowDownGame/game/guns/`目录与`Sniper.gd` | 现有枪资源与普通射弹路径 |

本轮再次通过GitHub读取并核对了默认分支、根README、RewardServer、BaseReward、RewardChoose、BaseAttachment、Bullet、BoomBoi、Sniper与相关目录；其余主项目源码在本次讨论前序审阅中已读取。引用不代表作者完成了所有源码全量审计。

可用于内容一致性比对的已知blob：

```text
README.md                                  d2afa3dce5f0ab1ac4323429afc04f569b61f9a5
TowDownGame/autoload/server/RewardServer.gd d3cf7663b27d662de8856e74c56cbba28dc39567
TowDownGame/game/reward/BaseReward.gd        4a3d33ea21dbdd15a11985819a51954e36cf00c7
TowDownGame/ui/widgets/RewardChoose.gd       b58f45139dad3afc89cf159504f66cb538f089c2
TowDownGame/game/attachments/BaseAttachment.gd f3be7c7df10ab8ced4077ed0624c6e753e6277fb
TowDownGame/game/bullets/Bullet.gd           e67e68cbb4b9a77d58bc670ba2046428baeb0710
TowDownGame/game/guns/BoomBoi.gd             3ae2d3c713361832d726ddda4dc2ee1ac77a5708
```

## 二、首要参考项目[S20]

这些文件提供具体实现思路，不能据此断言某参数移植后一定更好：

- `Godot-GameTemplate/addons/top_down/scenes/actors/actor.tscn`：受击shader混合与轻微挤压恢复。
- `Godot-GameTemplate/addons/top_down/scripts/actor/DamageDisplay.gd`：相近连续伤害按暴击状态聚合显示。
- `Godot-GameTemplate/addons/top_down/scripts/weapon_system/WeaponKickback.gd`：射击事件同步冲量。
- `Godot-GameTemplate/addons/top_down/scenes/projectiles/projectile.tscn`：命中表现、命中次数、寿命与复用相关组件。
- `Godot-GameTemplate/addons/great_games_library/autoload/SoundManager.gd`：独立播放与播放器复用思路。
- `Godot-GameTemplate/addons/great_games_library/resources/InstanceResource/InstanceResource.gd`：实例配置、活动对象与池回收；需另行验证重入和回收边界。

副参考：`Barren-Game/Godot Project/Environment/Building/BehindBuilding.gd` 的建筑遮挡淡出；`Barren-Game/Godot Project/Scenes/DamageIndicator.gd` 的重要命中分层。移植要保留本游戏风格，并检查引用依赖，不整套复制其辅助框架。

## 三、核对过的官方文档

[S21] Godot命令行：
`https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html`

用来核对`--version`、`--help`、`--import`、`--script`、`--headless`和导出参数的用途。本地二进制版本仍以实际检测为准；headless使用Dummy音频，不是听感验证。

[S22] AudioStreamPlayer：
`https://docs.godotengine.org/en/stable/classes/class_audiostreamplayer.html`

有限max_polyphony、超上限抢占、切换stream会停止现有播放等契约，用于设计音效压力测试；不等于推荐无限增加声部。

[S23] 暂停与process mode：
`https://docs.godotengine.org/en/stable/tutorials/scripting/pausing_games.html`

用于核对暂停时的物理/节点处理和菜单继续工作的边界；不能只暂停一个Timer就宣称全游戏暂停。

[S24] Godot用户数据路径：
`https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html`

用于迭代副本存档与原型隔离。只读原项目源码不意味着运行时自动使用不同存档，因此必须显式验证。

## 四、哪些是设计而不是事实

24枪、24配件、24持久天赋、12普通/特殊敌人、3Boss、6区域以及所有新名称/价格/触发值/性能目标，均是本计划给Codex的执行规格，不是对当前仓库内容的描述。

用户已经明确的是爽感优先、内容扩展、保留营地循环、9999试玩资源、金币购买天赋、Godot-GameTemplate首要参考与原型保护。此后提供的精确数量和阶段关口是设计落地默认，不冒充用户逐条说过的内容。

## 五、尚未做的事情

没有修改GitHub或用户D盘；没有复制用户本地项目；没有在本轮运行Godot；没有证明所有新增机制已经实现；没有得到H1/H2/H3真人验收；没有发布任何游戏资产。执行包只包含计划文档，不包含第三方游戏素材或字体文件。
