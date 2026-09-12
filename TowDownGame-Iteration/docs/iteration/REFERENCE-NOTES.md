# 参考与资产来源

首要参考 Godot-GameTemplate：

- `addons/top_down/scripts/damage/ActorDamage.gd`：受击短闪重新触发、受击和死亡声音分开、死亡表现先于对象回收。适配到 BaseMonster/Combat，没有搬运资源框架。
- `addons/top_down/scripts/actor/player/PlayerJuice.gd`：从伤害事件驱动反馈，断开旧订阅。保留原控制，普通命中不增加全局停帧。
- `addons/great_games_library/autoload/SoundManager.gd`：独立播放/回收思路。本版固定8声部，达到上限仅舍弃低优先命中装饰音，枪声独立。
- 遮挡对照：未找到可直接复用且更合适的独立遮挡模块；本版用既有 Godot 物理射线判断墙体，并做真正的墙体测试。没有虚构移植结果。

次要参考 Barren-Game：

- `Godot Project/WeaponsContents/BulletBehavior.gd`：子弹主体与尾迹分层、限时回收。保留本游戏的真实物理弹，不搬其按渲染帧移动的实现。
- `Godot Project/Particles/CriticalHitParticles.gd`：暴击有独立局部表现与音色，适配为独立聚合数字「暴击」和短闪。

资产：完整复用 TowDownGame 已有枪体、人物/怪物PNG图集、中文像素字体、音频和镇区资源。新电弧、爆炸边界与敌人预警为本次代码绘制；没有下载外部资产。源场景/脚本对应关系见 CONTENT-MANIFEST.json。

许可边界：TowDownGame README 声明 GNU GPL，但未包含完整逐资产授权表；Godot-GameTemplate 根 LICENSE 为 MIT；原项目粒子包 `Sprites/effect/part/LICENSE.txt` 标注 Kenney CC0。字体、其他音频/图集的逐项许可尚未独立核实，不能据此宣布可商业发行。本阶段只交付开发源码和本地入口，无商业发行声明。
