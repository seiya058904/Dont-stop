# M6 性能归因与对照

同一已有Godot 4.7.2 / Ryzen 7 9700X，headless、max-fps160。原M5Pressure：seed333、150敌人、至少400射弹、六种特殊机制、链电/爆炸/原激光；33秒运行，3秒预热。逐次源文件哈希、实体密度、伤害计数在benchmark索引。A/B只替换Combat和BaseMonster两个文件，隔离副本不修改主项目，没有减少压力或跳过伤害。

压力为引擎delta采样，不是GPU FPS；与长测主线程墙钟口径不混用。同步scope按self/inclusive计时，跳过含await函数；插桩开销不用于p99对照，文件逐字节恢复。原压力无Boss且150敌人触及召唤上限，另用M5BossCombat实跑三个Boss归因，不把不同运行耗时相加为单次帧预算。

| 批次 / 指标 | M5 | M6 |
| --- | --- | --- |
| 历史压力p99 ms | 48.485 | 不直接推断改善幅度 |
| 多进程审计并发，三次压力p99 ms | 75.000 / 95.833 / 80.108 | 77.778 / 82.052 / 75.000 |
| 审计结束后交替三次压力p99 ms | 16.667 / 33.333 / 40.397 | 17.289 / 17.600 / 49.864 |
| 后一批压力p99中位数 ms | 33.333 | 17.600 |
| 同批正常场景p95 / p99 ms | 8.333 / 8.333 | 8.333 / 8.333 |
| 长测墙钟p95 / p99 ms | 15.695 / 16.133 | 15.935 / 16.407 |

后一批仍与低密度长测并行，并非独占机器。M6两次达到33.3ms、第三次49.864ms，不能宣称稳定达标或已证明显著代码加速。同环境M5也能到16.667ms，历史值下降混有调度差异。正常场景未见明显退化，长测p99约+1.7%。按退出门允许的剩余瓶颈证据结束优化，不削弱玩法追数字。

主要累计self成本：普通Bullet物理3184.834ms/716429次；DemoEnemy绘制1513.788ms/422035次；BaseMonster状态823.767ms；运动回调763.838ms；枪支更新615.257ms；弹烟生成398.305ms；clear_line射线359.202ms；path_step寻路295.587ms。这不是单帧耗时。

只缓存稳定RID排除列表和按受击状态变化更新视觉。没有现成射弹池，rotary测试针对实际分配/回收，pool corruption不适用。剩余普通弹、绘制和物理成本需要更大架构变化，不在本轮安全收敛中贸然修改。

全部同步函数计数如下：AI按敌人ID，寻路/targeting、普通和特殊弹、tracking/ricochet/fragment/gravity/heat/disc、召唤与Boss分别列名。持续燃烧包含在BaseMonster._process，heat触发/cone单列。Timer回调有计数；原生signal投递和调度不能用脚本scope独立拆分，跨轮Timer/连接数见long-final.json，不把未采样成本写零。VFX/临时节点生成销毁函数同时保留。

| 样本 | 同步函数 / 机制 | 次数 | self ms | inclusive ms | max ms |
| --- | --- | ---: | ---: | ---: | ---: |
| profile-before.txt | game/bullets/Bullet.gd:_physics_process | 716429 | 3184.834 | 4807.657 | 25.946 |
| profile-before.txt | game/monster/DemoEnemy.gd:_draw | 422035 | 1513.788 | 1745.408 | 0.297 |
| profile-before.txt | game/monster/BaseMonster.gd:_process | 173220 | 823.767 | 856.344 | 0.735 |
| profile-before.txt | game/monster/BaseMonster.gd:_on_velocity_computed | 46871 | 763.838 | 763.838 | 0.171 |
| profile-before.txt | game/guns/BaseGun.gd:updateGun | 43038 | 615.257 | 615.257 | 0.189 |
| profile-before.txt | game/bullets/Bullet.gd:bulletSmoke | 12497 | 398.305 | 398.305 | 2.727 |
| profile-before.txt | autoload/Combat.gd:clear_line | 19572 | 359.202 | 359.202 | 0.257 |
| profile-before.txt | game/monster/BaseMonster.gd:_physics_process | 46971 | 357.906 | 1266.847 | 0.412 |
| profile-before.txt | game/monster/TacticalEnemy.gd:move_towards / E03 | 23210 | 336.934 | 400.005 | 0.461 |
| profile-before.txt | game/monster/TacticalEnemy.gd:move_towards / E07 | 19529 | 321.718 | 375.858 | 0.623 |
| profile-before.txt | game/monster/TacticalEnemy.gd:move_towards / E09 | 22883 | 321.357 | 406.676 | 0.487 |
| profile-before.txt | game/map/CombatArena.gd:path_step | 16351 | 295.587 | 463.470 | 0.628 |
| profile-before.txt | game/monster/TacticalEnemy.gd:move_towards / E11 | 13334 | 295.407 | 332.765 | 0.463 |
| profile-before.txt | game/monster/TacticalEnemy.gd:move_towards / E08 | 17361 | 276.837 | 355.681 | 0.671 |
| profile-before.txt | game/monster/TacticalEnemy.gd:_draw / E03 | 57431 | 260.701 | 492.622 | 0.226 |
| profile-before.txt | game/monster/TacticalEnemy.gd:_draw / E09 | 53669 | 253.132 | 467.382 | 0.167 |
| profile-before.txt | game/monster/BaseMonster.gd:_draw | 433227 | 237.136 | 237.136 | 0.281 |
| profile-before.txt | game/monster/TacticalEnemy.gd:_physics_process / E03 | 37156 | 218.275 | 723.472 | 0.494 |
| profile-before.txt | game/monster/BaseMonster.gd:receive_damage | 6629 | 205.611 | 1331.978 | 25.839 |
| profile-before.txt | game/monster/TacticalEnemy.gd:move_towards / E10 | 13488 | 200.439 | 232.495 | 0.414 |
| profile-before.txt | game/monster/TacticalEnemy.gd:_physics_process / E09 | 33691 | 185.341 | 592.017 | 0.515 |
| profile-before.txt | game/monster/TacticalEnemy.gd:_draw / E07 | 44520 | 175.838 | 349.588 | 0.312 |
| profile-before.txt | game/monster/TacticalEnemy.gd:move_towards / E12 | 10869 | 170.492 | 199.534 | 0.336 |
| profile-before.txt | game/bullets/Bullet.gd:_on_timer_timeout | 164878 | 169.424 | 169.424 | 0.082 |
| profile-before.txt | game/map/mapTown/Town.gd:onMonsterDeath | 4695 | 168.654 | 168.654 | 0.401 |
| profile-before.txt | game/monster/TacticalEnemy.gd:move_towards / E06 | 9395 | 162.750 | 183.426 | 0.317 |
| profile-before.txt | game/monster/TacticalEnemy.gd:_physics_process / E07 | 28165 | 151.851 | 619.989 | 0.682 |
| profile-before.txt | game/monster/TacticalEnemy.gd:_draw / E12 | 32515 | 145.468 | 275.767 | 0.153 |
| profile-before.txt | game/map/CombatArena.gd:nearest | 710 | 141.495 | 141.495 | 0.424 |
| profile-before.txt | game/monster/TacticalEnemy.gd:_draw / E06 | 29992 | 137.377 | 260.453 | 0.134 |
| profile-before.txt | game/monster/TacticalEnemy.gd:_draw / E08 | 41970 | 137.156 | 298.741 | 0.126 |
| profile-before.txt | game/monster/DemoEnemy.gd:_physics_process | 53061 | 134.953 | 995.166 | 0.416 |
| profile-before.txt | game/effects/GravityField.gd:_physics_process | 2003 | 131.638 | 141.916 | 0.969 |
| profile-before.txt | game/monster/TacticalEnemy.gd:_physics_process / E08 | 25297 | 130.714 | 547.015 | 0.731 |
| profile-before.txt | game/monster/TacticalEnemy.gd:_draw / E11 | 34450 | 121.391 | 257.422 | 0.244 |
| profile-bosses.txt | game/map/mapTown/Town.gd:depart | 3 | 114.818 | 141.672 | 135.145 |
| profile-before.txt | game/monster/TacticalEnemy.gd:_draw / E10 | 34609 | 106.537 | 242.055 | 0.137 |
| profile-before.txt | game/monster/TacticalEnemy.gd:_physics_process / E10 | 21372 | 101.119 | 399.191 | 21.442 |
| profile-before.txt | game/bullets/BulletShell.gd:_physics_process | 86576 | 100.078 | 100.078 | 0.087 |
| profile-before.txt | game/monster/TacticalEnemy.gd:_physics_process / E11 | 20667 | 97.697 | 430.462 | 0.472 |
| profile-before.txt | autoload/Combat.gd:_physics_process | 1987 | 94.642 | 94.642 | 0.159 |
| profile-bosses.txt | game/guns/MechanismGun.gd:_process | 6769 | 92.455 | 126.526 | 0.075 |
| profile-before.txt | game/bullets/Bullet.gd:_ready | 13206 | 90.399 | 90.399 | 0.145 |
| profile-before.txt | game/guns/BaseGun.gd:damage_context | 13827 | 84.416 | 84.416 | 0.144 |
| profile-before.txt | game/monster/BaseMonster.gd:_ready | 4845 | 79.542 | 79.542 | 2.301 |
| profile-before.txt | game/monster/TacticalEnemy.gd:_physics_process / E12 | 18578 | 77.414 | 276.948 | 0.344 |
| profile-before.txt | game/monster/TacticalEnemy.gd:_physics_process / E06 | 17187 | 73.150 | 256.576 | 0.336 |
| profile-bosses.txt | game/monster/BaseMonster.gd:_on_velocity_computed | 3852 | 72.732 | 72.732 | 0.213 |
| profile-before.txt | game/monster/TacticalEnemy.gd:onDie / E12 | 390 | 70.033 | 136.962 | 25.828 |
| profile-before.txt | game/monster/HostileZone.gd:_draw | 6208 | 68.695 | 68.695 | 0.055 |
| profile-before.txt | autoload/Combat.gd:hit | 7808 | 67.245 | 1490.944 | 25.853 |
| profile-before.txt | game/effects/CombatEffect.gd:_draw | 10476 | 65.074 | 65.074 | 0.082 |
| profile-before.txt | autoload/Combat.gd:explosion_context | 794 | 62.952 | 252.149 | 2.669 |
| profile-before.txt | game/map/mapTown/Town.gd:path_step | 16351 | 55.050 | 518.520 | 0.635 |
| profile-before.txt | game/bullets/Bullet.gd:fire | 13206 | 52.419 | 55.776 | 0.156 |
| profile-before.txt | game/monster/BaseMonster.gd:hitFlash | 5308 | 48.003 | 1224.518 | 25.860 |
| profile-before.txt | game/monster/DemoEnemy.gd:_on_animated_sprite_2d_frame_changed | 99134 | 46.385 | 46.385 | 0.084 |
| profile-bosses.txt | game/monster/BaseMonster.gd:_physics_process | 3852 | 41.950 | 173.293 | 0.485 |
| profile-before.txt | autoload/Combat.gd:arc | 231 | 41.290 | 106.067 | 14.418 |
| profile-bosses.txt | game/map/CombatArena.gd:nearest | 204 | 38.385 | 38.385 | 0.361 |
| profile-before.txt | game/monster/DemoEnemy.gd:_ready | 4441 | 36.193 | 109.496 | 0.165 |
| profile-before.txt | game/monster/TacticalEnemy.gd:onDie / E07 | 388 | 35.511 | 116.255 | 0.917 |
| profile-bosses.txt | game/guns/BaseGun.gd:_process | 6769 | 34.071 | 34.071 | 0.048 |
| profile-before.txt | game/monster/TacticalEnemy.gd:onDie / E09 | 392 | 33.947 | 100.477 | 0.633 |
| profile-before.txt | game/monster/TacticalEnemy.gd:onDie / E03 | 376 | 32.444 | 97.648 | 0.891 |
| profile-before.txt | game/monster/TacticalEnemy.gd:onDie / E11 | 392 | 32.294 | 97.732 | 0.713 |
| profile-before.txt | game/monster/TacticalEnemy.gd:onDie / E06 | 395 | 32.270 | 97.410 | 0.768 |
| profile-before.txt | game/bullets/MechanismProjectile.gd:_physics_process / ricochet | 4162 | 32.128 | 42.651 | 0.544 |
| profile-before.txt | game/monster/TacticalEnemy.gd:onDie / E08 | 389 | 32.128 | 97.458 | 0.990 |
| profile-before.txt | game/monster/TacticalEnemy.gd:onDie / E10 | 391 | 31.786 | 95.568 | 0.912 |
| profile-before.txt | game/bullets/MechanismProjectile.gd:_physics_process / missile | 4172 | 30.338 | 41.315 | 1.030 |
| profile-bosses.txt | game/monster/DemoEnemy.gd:_draw | 6904 | 29.839 | 34.408 | 0.117 |
| profile-before.txt | game/map/CombatArena.gd:cell | 32702 | 26.388 | 26.388 | 0.098 |
| profile-before.txt | game/monster/BaseMonster.gd:flip_h | 45856 | 26.324 | 26.324 | 0.054 |
| profile-before.txt | game/map/mapTown/Town.gd:prepare_region | 1 | 26.055 | 26.875 | 26.875 |
| profile-before.txt | game/bullets/MechanismProjectile.gd:_physics_process / disc | 2548 | 25.125 | 26.894 | 0.394 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:shot / B02 | 10 | 23.571 | 23.787 | 23.418 |
| profile-before.txt | game/effects/GravityField.gd:_draw | 2041 | 23.272 | 23.272 | 0.035 |
| profile-bosses.txt | game/monster/BaseMonster.gd:_process | 16606 | 22.512 | 22.512 | 0.128 |
| profile-before.txt | autoload/Combat.gd:sound | 7423 | 21.951 | 21.951 | 0.052 |
| profile-before.txt | autoload/Combat.gd:secondary_hit | 1575 | 21.696 | 59.823 | 0.818 |
| profile-bosses.txt | game/monster/DemoEnemy.gd:_physics_process | 4212 | 21.570 | 194.882 | 0.495 |
| profile-before.txt | game/monster/HostileZone.gd:_physics_process | 5821 | 21.476 | 213.503 | 2.676 |
| profile-before.txt | game/monster/TacticalEnemy.gd:shot / E10 | 2 | 21.397 | 21.492 | 21.422 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:zone / B01 | 4 | 19.128 | 19.165 | 18.913 |
| profile-before.txt | game/bullets/MechanismProjectile.gd:gravity_field / gravity | 38 | 18.398 | 18.474 | 17.242 |
| profile-bosses.txt | game/guns/MechanismGun.gd:_physics_process | 2810 | 17.109 | 17.109 | 0.170 |
| profile-bosses.txt | game/map/mapTown/Town.gd:prepare_region | 3 | 16.956 | 19.498 | 17.664 |
| profile-before.txt | game/bullets/MechanismProjectile.gd:_physics_process / shard | 1870 | 16.285 | 20.163 | 0.568 |
| profile-bosses.txt | game/map/CombatArena.gd:path_step | 940 | 15.653 | 56.397 | 0.413 |
| profile-before.txt | game/guns/BaseGun.gd:set_use | 705 | 15.186 | 20.308 | 0.187 |
| profile-before.txt | game/monster/TacticalEnemy.gd:summon / E07 | 390 | 14.634 | 14.634 | 0.251 |
| profile-before.txt | game/bullets/MechanismProjectile.gd:_physics_process / gravity | 1275 | 12.788 | 31.262 | 17.249 |
| profile-bosses.txt | game/monster/EnemyShot.gd:_physics_process | 3680 | 12.643 | 12.645 | 0.223 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:_physics_process / B03 | 889 | 12.541 | 17.305 | 0.676 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:_draw / B01 | 890 | 11.834 | 18.373 | 0.087 |
| profile-before.txt | game/guns/BaseGun.gd:_shootAnim | 231 | 11.223 | 11.223 | 2.867 |
| profile-before.txt | game/monster/TacticalEnemy.gd:receive_damage / E03 | 1463 | 10.068 | 129.530 | 0.911 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:_physics_process / B01 | 888 | 9.981 | 34.631 | 18.982 |
| profile-bosses.txt | autoload/server/LevelServer.gd:_timeout | 444 | 9.918 | 13.748 | 0.212 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:_physics_process / B02 | 889 | 9.679 | 42.824 | 23.597 |
| profile-before.txt | game/bullets/MechanismProjectile.gd:lock_target / missile | 78 | 9.552 | 20.406 | 0.740 |
| profile-bosses.txt | game/map/mapTown/Town.gd:roundVictory | 3 | 9.530 | 10.250 | 3.775 |
| profile-before.txt | autoload/Combat.gd:trace | 352 | 8.188 | 8.985 | 0.104 |
| profile-before.txt | game/guns/BaseGun.gd:_process | 1671 | 7.524 | 7.524 | 0.029 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:_draw / B03 | 891 | 7.400 | 14.144 | 0.047 |
| profile-bosses.txt | game/monster/HostileZone.gd:_physics_process | 556 | 7.375 | 7.438 | 0.381 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:_draw / B02 | 891 | 6.266 | 11.140 | 0.052 |
| profile-before.txt | game/monster/TacticalEnemy.gd:receive_damage / E09 | 904 | 6.215 | 120.572 | 0.657 |
| profile-before.txt | game/effects/CombatEffect.gd:_process | 9103 | 6.133 | 6.133 | 0.027 |
| profile-bosses.txt | game/guns/MechanismGun.gd:_draw | 6775 | 5.488 | 5.488 | 0.046 |
| profile-before.txt | game/guns/BaseGun.gd:cancel_actions | 484 | 5.207 | 5.207 | 0.027 |
| profile-bosses.txt | game/map/mapTown/Town.gd:path_step | 940 | 4.891 | 61.288 | 0.421 |
| profile-before.txt | game/monster/BaseMonster.gd:setData | 4845 | 4.810 | 4.810 | 0.037 |
| profile-bosses.txt | game/monster/BaseMonster.gd:_ready | 13 | 4.672 | 4.693 | 2.339 |
| profile-bosses.txt | game/monster/BaseMonster.gd:_draw | 6904 | 4.569 | 4.569 | 0.010 |
| profile-before.txt | game/monster/BaseMonster.gd:apply_burn | 672 | 4.165 | 4.165 | 0.051 |
| profile-before.txt | game/guns/BaseGun.gd:_physics_process | 3959 | 4.068 | 4.068 | 0.050 |
| profile-bosses.txt | game/monster/HostileZone.gd:_draw | 565 | 3.871 | 3.871 | 0.060 |
| profile-bosses.txt | game/map/mapTown/Town.gd:onTimeTick | 444 | 3.830 | 3.830 | 0.024 |
| profile-before.txt | game/bullets/MechanismProjectile.gd:_physics_process / fragment | 500 | 3.789 | 4.369 | 0.283 |
| profile-before.txt | game/monster/BaseMonster.gd:setDeathCallBack | 4845 | 3.227 | 3.227 | 0.034 |
| profile-before.txt | autoload/Combat.gd:cone | 38 | 3.089 | 7.733 | 0.639 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:move_towards / B01 | 186 | 3.077 | 3.517 | 0.077 |
| profile-before.txt | autoload/Combat.gd:explosion | 306 | 3.004 | 49.844 | 1.064 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:move_towards / B02 | 182 | 2.981 | 7.256 | 0.089 |
| profile-before.txt | game/effects/CombatEffect.gd:_ready | 1377 | 2.904 | 2.904 | 0.048 |
| profile-bosses.txt | game/monster/BaseMonster.gd:flip_h | 3847 | 2.657 | 2.657 | 0.045 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:move_towards / B03 | 186 | 2.641 | 3.264 | 0.176 |
| profile-bosses.txt | game/map/CombatArena.gd:_ready | 3 | 2.505 | 2.536 | 0.949 |
| profile-bosses.txt | game/map/CombatArena.gd:cell | 1893 | 2.381 | 2.381 | 0.030 |
| profile-before.txt | game/monster/TacticalEnemy.gd:_ready / E03 | 404 | 2.238 | 12.244 | 0.106 |
| profile-before.txt | game/monster/TacticalEnemy.gd:receive_damage / E07 | 567 | 2.176 | 127.078 | 1.132 |
| profile-before.txt | game/monster/TacticalEnemy.gd:_ready / E06 | 404 | 2.168 | 11.919 | 0.175 |
| profile-before.txt | game/monster/TacticalEnemy.gd:_ready / E07 | 404 | 2.124 | 12.131 | 0.114 |
| profile-before.txt | game/monster/TacticalEnemy.gd:_ready / E08 | 404 | 2.068 | 12.211 | 0.175 |
| profile-before.txt | game/monster/TacticalEnemy.gd:_ready / E09 | 404 | 2.053 | 12.035 | 0.172 |
| profile-before.txt | game/monster/TacticalEnemy.gd:_ready / E10 | 403 | 2.044 | 12.174 | 0.146 |
| profile-before.txt | game/monster/TacticalEnemy.gd:_ready / E11 | 403 | 2.040 | 11.691 | 0.089 |
| profile-before.txt | game/monster/TacticalEnemy.gd:_ready / E12 | 403 | 2.002 | 11.979 | 0.161 |
| profile-before.txt | game/bullets/BulletShell.gd:_ready | 1431 | 1.802 | 1.802 | 0.043 |
| profile-before.txt | game/monster/TacticalEnemy.gd:receive_damage / E08 | 402 | 1.598 | 105.395 | 1.022 |
| profile-before.txt | game/bullets/BulletShell.gd:start | 1431 | 1.555 | 1.555 | 0.072 |
| profile-before.txt | game/monster/TacticalEnemy.gd:receive_damage / E10 | 406 | 1.541 | 103.442 | 0.948 |
| profile-before.txt | game/monster/TacticalEnemy.gd:receive_damage / E11 | 408 | 1.539 | 105.901 | 0.737 |
| profile-before.txt | game/monster/TacticalEnemy.gd:receive_damage / E12 | 390 | 1.517 | 144.962 | 25.844 |
| profile-before.txt | game/monster/TacticalEnemy.gd:receive_damage / E06 | 401 | 1.509 | 105.466 | 0.791 |
| profile-bosses.txt | game/map/CombatArena.gd:spawn_near | 13 | 1.473 | 1.495 | 0.257 |
| profile-before.txt | game/monster/HostileZone.gd:_ready | 403 | 1.312 | 1.312 | 0.025 |
| profile-before.txt | game/bullets/MechanismProjectile.gd:split / shard | 8 | 1.261 | 1.722 | 0.288 |
| profile-bosses.txt | game/monster/DemoEnemy.gd:_on_animated_sprite_2d_frame_changed | 1740 | 1.157 | 1.157 | 0.003 |
| profile-before.txt | game/guns/BaseGun.gd:shot_context | 231 | 1.127 | 2.898 | 0.058 |
| profile-before.txt | game/monster/TacticalEnemy.gd:remember / E03 | 1046 | 1.106 | 1.106 | 0.004 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:_ready / B03 | 1 | 0.860 | 1.852 | 1.852 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:_ready / B02 | 1 | 0.841 | 1.914 | 1.914 |
| profile-before.txt | game/map/CombatArena.gd:_ready | 1 | 0.820 | 0.820 | 0.820 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:summon / B02 | 2 | 0.809 | 1.821 | 0.940 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:summon / B01 | 2 | 0.781 | 1.719 | 0.986 |
| profile-before.txt | game/bullets/BulletShell.gd:_on_timer_timeout | 1383 | 0.760 | 0.760 | 0.005 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:_ready / B01 | 1 | 0.748 | 3.107 | 3.107 |
| profile-before.txt | game/monster/TacticalEnemy.gd:zone / E03 | 19 | 0.721 | 0.814 | 0.066 |
| profile-bosses.txt | autoload/server/LevelServer.gd:getScoreboard | 3 | 0.638 | 0.638 | 0.226 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:shot / B03 | 24 | 0.572 | 0.977 | 0.133 |
| profile-bosses.txt | game/monster/EnemyShot.gd:_ready | 34 | 0.561 | 0.579 | 0.048 |
| profile-before.txt | game/monster/TacticalEnemy.gd:remember / E09 | 484 | 0.512 | 0.512 | 0.004 |
| profile-bosses.txt | autoload/Combat.gd:_actor_added | 553 | 0.512 | 0.512 | 0.006 |
| profile-before.txt | game/monster/EnemyShot.gd:_physics_process | 76 | 0.498 | 0.498 | 0.016 |
| profile-before.txt | game/bullets/MechanismProjectile.gd:_ready / missile | 78 | 0.411 | 1.047 | 0.026 |
| profile-before.txt | game/monster/TacticalEnemy.gd:zone / E10 | 8 | 0.315 | 0.351 | 0.060 |
| profile-before.txt | game/bullets/MechanismProjectile.gd:_ready / ricochet | 39 | 0.314 | 0.661 | 0.089 |
| profile-before.txt | game/bullets/MechanismProjectile.gd:_draw / disc | 38 | 0.311 | 0.311 | 0.015 |
| profile-bosses.txt | autoload/Combat.gd:clear_line | 23 | 0.284 | 0.316 | 0.023 |
| profile-before.txt | game/bullets/MechanismProjectile.gd:_draw / ricochet | 39 | 0.267 | 0.267 | 0.017 |
| profile-before.txt | game/monster/TacticalEnemy.gd:perform_attack / E08 | 2 | 0.267 | 0.441 | 0.240 |
| profile-before.txt | game/bullets/MechanismProjectile.gd:_ready / shard | 39 | 0.228 | 0.554 | 0.039 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:zone / B03 | 4 | 0.227 | 0.256 | 0.068 |
| profile-before.txt | game/bullets/MechanismProjectile.gd:_ready / gravity | 38 | 0.226 | 0.563 | 0.039 |
| profile-before.txt | game/bullets/MechanismProjectile.gd:_ready / disc | 38 | 0.203 | 0.497 | 0.021 |
| profile-before.txt | game/guns/BaseGun.gd:_ready | 9 | 0.201 | 0.456 | 0.099 |
| profile-before.txt | game/bullets/MechanismProjectile.gd:_draw / missile | 76 | 0.182 | 0.182 | 0.006 |
| profile-bosses.txt | autoload/server/LevelServer.gd:return_to_camp | 3 | 0.166 | 0.476 | 0.170 |
| profile-bosses.txt | autoload/server/LevelServer.gd:victory | 3 | 0.164 | 10.952 | 4.010 |
| profile-bosses.txt | game/monster/EnemyShot.gd:_draw | 34 | 0.164 | 0.164 | 0.013 |
| profile-bosses.txt | game/guns/BaseGun.gd:updateGun | 5 | 0.160 | 0.160 | 0.039 |
| profile-bosses.txt | game/map/mapTown/Town.gd:onMonsterDeath | 3 | 0.154 | 0.159 | 0.140 |
| profile-bosses.txt | game/map/mapTown/Town.gd:onRoundEnd | 3 | 0.153 | 0.153 | 0.057 |
| profile-bosses.txt | game/guns/BaseGun.gd:cancel_actions | 16 | 0.142 | 0.142 | 0.017 |
| profile-bosses.txt | game/monster/DemoEnemy.gd:_ready | 13 | 0.135 | 4.835 | 2.357 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:perform_attack / B03 | 6 | 0.133 | 1.122 | 0.662 |
| profile-before.txt | game/bullets/MechanismProjectile.gd:_draw / gravity | 38 | 0.123 | 0.123 | 0.007 |
| profile-before.txt | game/monster/TacticalEnemy.gd:choose_attack / E03 | 19 | 0.123 | 0.937 | 0.073 |
| profile-before.txt | game/bullets/MechanismProjectile.gd:_draw / shard | 39 | 0.120 | 0.120 | 0.009 |
| profile-before.txt | game/bullets/MechanismProjectile.gd:_ready / fragment | 24 | 0.117 | 0.325 | 0.022 |
| profile-before.txt | game/monster/EnemyShot.gd:_ready | 2 | 0.093 | 0.093 | 0.061 |
| profile-bosses.txt | autoload/Combat.gd:_ready | 1 | 0.090 | 0.099 | 0.099 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:perform_attack / B01 | 6 | 0.085 | 1.819 | 1.004 |
| profile-bosses.txt | game/map/CombatArena.gd:_draw | 3 | 0.083 | 0.083 | 0.034 |
| profile-before.txt | autoload/Combat.gd:_ready | 1 | 0.080 | 0.080 | 0.080 |
| profile-before.txt | game/map/mapTown/Town.gd:depart | 1 | 0.080 | 27.110 | 27.110 |
| profile-bosses.txt | autoload/server/LevelServer.gd:roundStart | 3 | 0.079 | 0.288 | 0.115 |
| profile-bosses.txt | game/map/mapTown/Town.gd:onRoundStart | 3 | 0.077 | 0.077 | 0.033 |
| profile-before.txt | game/effects/GravityField.gd:_ready | 38 | 0.076 | 0.076 | 0.006 |
| profile-bosses.txt | game/guns/MechanismGun.gd:cancel_actions | 16 | 0.073 | 0.215 | 0.024 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:onDie / B02 | 1 | 0.069 | 0.078 | 0.078 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:onDie / B03 | 1 | 0.068 | 0.209 | 0.209 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:perform_attack / B02 | 5 | 0.066 | 25.717 | 23.585 |
| profile-before.txt | game/bullets/MechanismProjectile.gd:begin_return / disc | 37 | 0.064 | 0.064 | 0.010 |
| profile-bosses.txt | game/map/mapTown/Town.gd:spawn_near | 13 | 0.064 | 1.559 | 0.266 |
| profile-before.txt | game/guns/BaseGun.gd:_init | 9 | 0.062 | 0.062 | 0.012 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:onDie / B01 | 1 | 0.062 | 0.073 | 0.073 |
| profile-bosses.txt | autoload/Combat.gd:hit | 3 | 0.057 | 0.565 | 0.275 |
| profile-bosses.txt | game/monster/BaseMonster.gd:receive_damage | 3 | 0.056 | 0.470 | 0.250 |
| profile-before.txt | game/monster/TacticalEnemy.gd:choose_attack / E10 | 8 | 0.055 | 0.406 | 0.067 |
| profile-bosses.txt | autoload/Combat.gd:sound | 3 | 0.054 | 0.054 | 0.022 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:zone / B02 | 1 | 0.053 | 0.059 | 0.059 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:choose_attack / B01 | 6 | 0.049 | 19.214 | 18.922 |
| profile-before.txt | game/map/mapTown/Town.gd:clear_practice | 1 | 0.048 | 0.097 | 0.097 |
| profile-before.txt | game/monster/TacticalEnemy.gd:perform_attack / E03 | 8 | 0.044 | 0.054 | 0.007 |
| profile-before.txt | game/bullets/MechanismProjectile.gd:lock_target / gravity | 38 | 0.039 | 0.039 | 0.002 |
| profile-before.txt | game/bullets/MechanismProjectile.gd:lock_target / shard | 39 | 0.039 | 0.039 | 0.002 |
| profile-bosses.txt | game/monster/HostileZone.gd:_ready | 9 | 0.039 | 0.039 | 0.006 |
| profile-bosses.txt | game/guns/BaseGun.gd:set_use | 2 | 0.038 | 0.053 | 0.049 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:choose_attack / B03 | 6 | 0.038 | 0.294 | 0.076 |
| profile-before.txt | game/bullets/MechanismProjectile.gd:lock_target / disc | 38 | 0.037 | 0.037 | 0.001 |
| profile-before.txt | game/bullets/MechanismProjectile.gd:lock_target / ricochet | 39 | 0.037 | 0.037 | 0.002 |
| profile-bosses.txt | game/map/mapTown/Town.gd:clear_practice | 3 | 0.037 | 0.092 | 0.039 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:remember / B01 | 18 | 0.037 | 0.037 | 0.005 |
| profile-bosses.txt | autoload/server/LevelServer.gd:can_start | 6 | 0.033 | 0.033 | 0.010 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:fan / B02 | 2 | 0.033 | 23.820 | 23.568 |
| profile-before.txt | game/map/CombatArena.gd:_draw | 1 | 0.032 | 0.032 | 0.032 |
| profile-bosses.txt | autoload/Combat.gd:_refresh_exclusions | 6 | 0.032 | 0.032 | 0.007 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:remember / B03 | 36 | 0.032 | 0.032 | 0.003 |
| profile-bosses.txt | autoload/server/LevelServer.gd:boss_defeated | 3 | 0.030 | 10.982 | 4.020 |
| profile-before.txt | game/bullets/MechanismProjectile.gd:_draw / fragment | 24 | 0.029 | 0.029 | 0.002 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:choose_attack / B02 | 5 | 0.025 | 0.084 | 0.066 |
| profile-before.txt | game/monster/TacticalEnemy.gd:choose_attack / E08 | 8 | 0.023 | 0.023 | 0.003 |
| profile-bosses.txt | game/monster/BaseMonster.gd:setData | 13 | 0.023 | 0.023 | 0.006 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:receive_damage / B01 | 1 | 0.023 | 0.125 | 0.125 |
| profile-before.txt | game/map/mapTown/Town.gd:onRoundStart | 1 | 0.022 | 0.022 | 0.022 |
| profile-before.txt | game/monster/TacticalEnemy.gd:choose_attack / E07 | 8 | 0.022 | 0.022 | 0.004 |
| profile-before.txt | game/monster/TacticalEnemy.gd:perform_attack / E10 | 2 | 0.022 | 21.517 | 21.435 |
| profile-bosses.txt | game/guns/BaseGun.gd:_ready | 1 | 0.021 | 0.054 | 0.054 |
| profile-bosses.txt | game/monster/DemoEnemy.gd:onAtk | 39 | 0.021 | 0.021 | 0.001 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:remember / B02 | 22 | 0.021 | 0.021 | 0.002 |
| profile-before.txt | game/monster/TacticalEnemy.gd:perform_attack / E07 | 2 | 0.020 | 0.093 | 0.053 |
| profile-bosses.txt | autoload/server/LevelServer.gd:_ready | 1 | 0.017 | 0.018 | 0.018 |
| profile-bosses.txt | game/guns/BaseGun.gd:_init | 1 | 0.017 | 0.017 | 0.017 |
| profile-before.txt | game/map/mapTown/Town.gd:_ready | 1 | 0.015 | 0.015 | 0.015 |
| profile-before.txt | game/monster/TacticalEnemy.gd:remember / E10 | 12 | 0.015 | 0.015 | 0.002 |
| profile-bosses.txt | autoload/Combat.gd:_actors_changed | 13 | 0.013 | 0.013 | 0.003 |
| profile-bosses.txt | game/map/mapTown/Town.gd:_ready | 1 | 0.013 | 0.013 | 0.013 |
| profile-before.txt | game/monster/EnemyShot.gd:_draw | 2 | 0.012 | 0.012 | 0.006 |
| profile-before.txt | game/guns/BaseGun.gd:setOwner | 9 | 0.011 | 0.011 | 0.002 |
| profile-bosses.txt | autoload/server/LevelServer.gd:timerStop | 6 | 0.010 | 0.010 | 0.003 |
| profile-bosses.txt | game/monster/BaseMonster.gd:setDeathCallBack | 13 | 0.010 | 0.010 | 0.002 |
| profile-bosses.txt | autoload/server/LevelServer.gd:resetLevelInfo | 3 | 0.008 | 0.008 | 0.003 |
| profile-before.txt | game/map/mapTown/Town.gd:_on_shop_body_entered | 1 | 0.007 | 0.007 | 0.007 |
| profile-before.txt | game/map/mapTown/Town.gd:onGameStart | 1 | 0.007 | 0.007 | 0.007 |
| profile-bosses.txt | game/guns/MechanismGun.gd:_ready | 1 | 0.007 | 0.061 | 0.061 |
| profile-bosses.txt | game/map/mapTown/Town.gd:_on_shop_body_entered | 1 | 0.007 | 0.007 | 0.007 |
| profile-bosses.txt | autoload/server/LevelServer.gd:timerStart | 3 | 0.006 | 0.006 | 0.002 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:receive_damage / B02 | 1 | 0.006 | 0.128 | 0.128 |
| profile-bosses.txt | game/monster/TacticalEnemy.gd:receive_damage / B03 | 1 | 0.005 | 0.255 | 0.255 |
| profile-before.txt | game/monster/TacticalEnemy.gd:remember / E08 | 2 | 0.003 | 0.003 | 0.002 |
| profile-bosses.txt | game/map/mapTown/Town.gd:onGameStart | 1 | 0.003 | 0.003 | 0.003 |
| profile-before.txt | game/monster/TacticalEnemy.gd:remember / E07 | 2 | 0.002 | 0.002 | 0.001 |
| profile-bosses.txt | game/guns/BaseGun.gd:setOwner | 1 | 0.001 | 0.001 | 0.001 |
