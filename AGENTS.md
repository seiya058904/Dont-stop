# Don't Stop：项目与验证指南

## 工作区与权威入口

- Git 根是本目录；Godot 项目是 `Don't stop/project.godot`，不是外层目录。命令中的项目路径必须整体引用，避免空格和英文撇号被 shell 拆分。
- `boot/Boot.tscn` 是配置入口，加载 `game/map/Main.tscn`；Web 启动界面由 `web/loader.html` 提供。以上路径均相对于 Godot 项目目录。
- 项目内 `autoload/` 管理全局状态，`game/` 包含玩法与配置，`ui/` 包含界面，`Sprites/`、`audio/`、`fonts/`、`shader/` 与 `addons/` 是产品资源。`tests/` 是原生回归场景，`tools/` 是导出、浏览器与证据校验工具。
- 根 README 提供正式下载与试玩入口。封板版本为 `v1.3.3`；Release tag 指向通过验收的 `main`，Pages 发布该 main 构建中实际测试过的 Web bytes。今后的仅文档提交可以不重新部署游戏；不能据 Git 最新 SHA 推断线上身份。
- `Don't stop/docs/iteration/release-v1.3.3.md` 是最终收口记录，`release-v1.3.2.md` 保留性能与 Boss 审计；其他 iteration 文档保留历史证据，旧 SHA、性能样本和未完成事项不代表当前状态。

## 运行与验证

使用 Godot **4.7.2-stable** 及匹配导出模板、Python 3、CI Node **22**、Playwright **1.60.0** 及其配套 Chromium。权威版本见 `.github/workflows/` 和 `.github/actions/setup-browser/action.yml`。以下命令从 Git 根运行，`GODOT` 指向实际引擎；Windows 用等价参数并等待进程退出。

```bash
"$GODOT" --path "Don't stop"
"$GODOT" --headless --path "Don't stop" --editor --import --quit --log-file "$PWD/import.log"
python "Don't stop/tools/b194_import_check.py" "Don't stop" import.log
"$GODOT" --headless --path "Don't stop" --quit-after 60000 res://tests/B194Contracts.tscn
"$GODOT" --headless --path "Don't stop" --quit-after 60000 res://tests/P0SaveSanity.tscn
"$GODOT" --headless --path "Don't stop" --quit-after 60000 res://tests/BaselineRegression.tscn
node "Don't stop/tools/stress-completion.test.js"
python "Don't stop/tools/test-menu-soak-policy.py"
```

按改动选择额外场景，以当前 CI 中的调用为准。新缓存的首次导入可能先报告字体/光标尚未导入；只有导入校验器确认资源已生成，且后续 B194Contracts 通过，才能接受这些特定早期诊断。其他脚本错误或失败断言不能忽略。

正式候选须运行 `native-tests.yml` 中全部 active cases（当前 56 个 contracts 和 6 个 pressure 调用，参数也是用例身份的一部分），含 DeepQuality、CameraTransitions、WebPhysicsContracts、Boss full/pressure/contracts。`historical-evidence` 是显式选用的历史测量，不计 active gate。用隔离源码副本和 APPDATA/user-data 运行会写 evidence 的场景，避免污染 canonical 记录或真实存档。通过必须同时有正常退出、PASS 断言且无 FAIL/SCRIPT ERROR；不能把旧提交结果转记到新候选。

完整 active native acceptance 不传引擎 `--quit-after`：该参数按 render frames 终止，长套件可能以 exit 0、部分 PASS 提前退出。保留外部 wall-time timeout，等夹具自然完成；M6/M8 必须有 30 关完整记录及结束标记。contracts job 60 分钟，M6/M8 单用例预算分别 1800/2400 秒，其他短用例 900 秒；pressure 保留 1800 秒预算。快速 preflight 的有限帧防挂不能替代完整验收。

M10Bosses headless `full` 会自动将 stage 10/20/30 放入独立 headless 进程和用户数据目录，并给子用例带 `--fixed-fps 120`（两个 render steps / 一个 60 Hz physics tick）。bot 按 render clock 开火；固定 RNG seed 不固定 uncapped 相位，连续战斗还会携带 bot clock、cooldowns、RNG 消耗及 epoch 派生的 hazard seed。隔离只用于夹具，未设产品 FPS 上限，也不手工改生产状态；budget/TTK 以实际 physics ticks 计算，wall_seconds 单列。单独运行 `only10/only20/only30` 子用例时须自行在 scene 前带 `--fixed-fps 120`。不能改 Boss、加血或暂停 DPS 使测试通过。

导出预设名必须精确匹配 `Don't stop/export_presets.cfg`；输出路径相对于项目目录：

```bash
mkdir -p "Don't stop/build/web" "Don't stop/build/windows"
"$GODOT" --headless --path "Don't stop" --export-release "Web Release" build/web/index.html
"$GODOT" --headless --path "Don't stop" --export-release "Windows x64 Release" "build/windows/Don't stop.exe"
python "Don't stop/tools/stamp-build-identity.py" "Don't stop/build/web" "$BUILD_SHA" output/build-identity.json
python -m http.server 8788 --bind 127.0.0.1 --directory "Don't stop/build/web"
# 另开终端，确保 Node 能解析已安装的 playwright；浏览器证据保持在被忽略目录。
mkdir -p output
node "Don't stop/tools/smoke-web.js" http://127.0.0.1:8788/index.html output
node "Don't stop/tools/web-loader-check.js" http://127.0.0.1:8788/index.html output/loader
node "Don't stop/tools/save-audit-web.js" http://127.0.0.1:8788/index.html output/save
node "Don't stop/tools/web-save-durable.js" http://127.0.0.1:8788/index.html output/durable
node "Don't stop/tools/web-aim-e2e.js" http://127.0.0.1:8788/index.html output/aim-core core
node "Don't stop/tools/web-aim-e2e.js" http://127.0.0.1:8788/index.html output/aim-fault fault
node "Don't stop/tools/web-menu-return-e2e.js" http://127.0.0.1:8788/index.html output/menu-return 20
node "Don't stop/tools/verify-pages-deployment.js" http://127.0.0.1:8788/index.html "$BUILD_SHA" output/build-identity.json output/identity
```

Identity 只在未 stamp 的导出上写一次；之后测试、打包、部署同一目录，不重新导出替换 bytes。Web full 还包括 `web-b11-stagerun.js`。线上核验使用正式 URL 与对应 build-identity.json；SHA、聚合摘要及 wasm/pck/js 单文件摘要都必须一致。

`Don't stop/PLAY_GAME.bat` 会导出并启动 Windows 源码版本，依赖项目内 `README-PLAY.md` 指定的工作区便携工具；`Don't stop/PLAY_WEB.bat` 只服务已有 `build/web`，不会自动导出。不要删除这些入口依赖。

## 必须保留的约束

- 保持玩法、数值、RNG 序列及存档兼容性。开发存档目录为 `TowDownGame-Iteration`，`public_release` 使用 `TowDownGame`；测试须隔离用户数据，不能覆盖真实存档。
- Web 保存只有 IndexedDB 提交并确认指定快照后才能报告成功；失败保持 dirty 状态与重试/导出能力。不得把仅写入 MEMFS 或调用文件同步当作持久化成功。
- 坏档“明确建立新体验档”是串行恢复事务：`creating_new_save` 到确认成功/失败之间，恢复弹窗保持顶层暂停、退出按钮禁用并持有键盘焦点；购买/退款/补给/携带栏/装备/出发/离开入口拒绝写操作。不能仅在 `save_camp()` 返回 pending 后仍接受修改，也不能用递增 revision 掩盖丢状态。成功恢复新档后才解除锁；失败恢复 `.previous`、保留原文并允许重试或明确退出。普通保存保持既有 revision/dirty/精确快照确认语义。
- SceneManager 的转场图案有动态路径；保留 Boot 中的资源引用与导出 include filter。不要因未出现静态调用而删除资源。
- `.godot/`、`build/`、隔离测试副本、临时 profile/log/ZIP、Python 字节码可再生成；清理前核对用途、跟踪状态、引用和唯一证据，并逐个验证目标。正式资源、资源旁 `.import` 描述、canonical docs、最终审计/性能证据、release provenance、fixture 和历史原件须保留。根 `archive/` 含历史原件与 PLAY_GAME 所需工具，不能整体删除。
- Pages 身份由提交 SHA、`index.wasm || index.pck || index.js` 的摘要及各文件哈希共同证明；使用 `tools/stamp-build-identity.py`、`tools/verify-pages-deployment.js` 的实际接口，不能仅以 HTTP 200 验收。

## Camera、插值与预热

- 模拟仍为 60 Hz。根 viewport 默认不插值；Hero、敌人、敌弹、跟踪 Anchor/Camera 显式开启物理插值。角色翻面/攻击 artwork、武器 recoil、UI 和按渲染帧推进的效果保持原有时钟。
- Camera look-ahead 与 shake 在 physics clock 上生成快照。传送/战斗与营地转换统一 align、reset_smoothing、reset_physics_interpolation，再 force_update_scroll；不能遗漏初始快照重置。只在最终 display vertices 像素对齐，不能重新开启逻辑 transform snapping，后者会在高分辨率下重新形成运动台阶。
- Web 首枪预热只在 Web 菜单初始化路径执行，受 OS feature 与幂等保护；等待实际 frame_post_draw 完成后才通知 loader 揭开覆盖层。禁止改成 Start、进入营地或战斗转场时同步预热。
- 只预热 trace 已定位的 Canvas primitive、muzzle 与烟尘 instancing/material variants。使用无玩法组的惰性绘制和实际资源，不创建游戏角色/粒子 emitter、不消耗玩法 RNG、不删除效果或降低画质。不能用泛化全资源预热替代定位。

## 性能证据口径

- 1080p/4K、60/高刷新分别实测；D/P 各按真实有效 physics ticks 与稳定窗口核验时长，多轮交替并记录引擎、浏览器、GPU、viewport、源码与 payload 身份。
- 冷路径使用 fresh browser 和 fresh storage、真实键鼠输入，记录首/二/三枪与 Start/营地/转场 rAF。CDP trace、WebGL 调用、游戏事件必须共用时间线；trace buffer 覆盖不足的样本不能归因后半程慢轮。
- Godot process interval、rAF 间隔、CPU/GPU 工作时长和 first rendered pixel 不是同一个指标；输入至像素观测也不是物理显示器 input-to-photon。像素 readback/逐帧诊断会扰动性能，诊断样本独立于性能验收。
- 随机慢样本只在复现并同步获得完整 trace/profiler/事件证据后归因；否则保留为未定环境/调度波动。不能根据均值宣称所有场景 FPS 提升，不能把终止时的 evidence dump 长任务计入战斗窗口。
- Boss 机制断言必须观察真正执行的攻击，不能用 windup 代替；M10 的固定测试步长保持 bot/physics 相位可复现，保留 8 HP、自由开火与真实伤害/输入。不能修改生产 Boss 来满足某次测试轨迹。

## CI/CD 与发布

- `deploy-pages.yml`：PR 做 native preflight 和独立 runner 的 smoke/menu-return 必需 gates；main 快速链做 import、B194Contracts/P0SaveSanity、一次 Web export、loader/smoke/identity，然后部署同一 bytes 并验证线上身份。仅文档变更跳过游戏构建/部署。
- 月度、Release published、manual full Web acceptance 包含 smoke、save-audit（含 `web-save-durable.js` 的真实故障/恢复事务测试）、aim core/fault、20 次 menu-return soak、stages-fair。manual 默认不部署，只有 main 且 `deploy=true` 才上线。完整 active native 包含 64 个调用；R1Persistence/R1RecoveryUI 固定覆盖普通保存、坏档事务 pending、旧确认、失败/重试/退出与确认后购买。
- `native-tests.yml`：月度、Release published、manual 完整 active native acceptance，独立 contracts/pressure jobs；历史证据按显式参数选择。`build-windows.yml` 是 manual headless export/package，不需启动本地 Windows 游戏。
- Release 为非 draft、非 prerelease 的正式 patch tag。Windows/Web ZIP 与 SHA-256 按既有命名上传；下载回验。tag 必须指向已验证 main，Web 资产优先复用经过验收的 Pages artifact，不将同 SHA 的重新构建视为同 bytes。
- 普通文档维护不触发重型验收或新 Release。发版时最终代码、最终包、实际 Actions run 与在线身份须关联；保留历史失败及最终修复证据，不把信息诊断写成零告警。

修改保持单目的；先检查现有工作区，完成适用回归、构建、入口 smoke 和 `git diff --check`，再审阅最终 diff。发布、tag、远端配置与历史改写必须有明确授权。
