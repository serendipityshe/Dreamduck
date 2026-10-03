# A733 基础运行验证

日期：2026-10-03。记录对应 [GitHub issue #1](https://github.com/serendipityshe/Dreamduck/issues/1)，证据来自用户提供的香橙派终端截图和健康查询 JSON。

## 环境与源码

- Orange Pi Zero 3W，Allwinner A733，6GB RAM，64GB microSD。
- 主板设备树已读取：model 为 `Orange Pi Zero 3W`，compatible 包含 `xunlong,orangepi-zero3w` 和 `arm,sun60iw2p1`。
- Armbian 26.8.1 Minimal，Debian 13（Trixie），系统版本输出为 Debian 13.6，架构为 `aarch64`。
- 工单记录的内核为 `6.6.98-vendor-sun60iw2`。
- 主板工具链：`rustc 1.99.0`、`cargo 1.99.0`。
- 源码分发包基线为 `1fa84386f07884e27866411bc1ba166977bced95`（Microduck 0.15.1）。主板工作目录为 `~/dreamduck-work`，GitHub 和 Gitea 的 HTTPS 克隆均遇到连接中断，源码改用 SSH/SCP 传输 Git bundle。
- 健康报告中的 revision 为 `null`；主板 `git rev-parse HEAD` 已单独确认是上述基线提交。

## 编译与运行命令

在主板源码目录中：

```bash
cargo build --locked -p robotd -p robotctl -j 2
```

用户的编译截图显示两个程序均完成构建，结束行是 `Finished dev profile [unoptimized + debuginfo] target(s) in 5m 43s`。随后主板成功运行了 `robotd`，并用 `robotctl` 查询到 0.15.1 的服务版本。

终端 1：

```bash
./target/debug/robotd --fake --no-policy --socket /tmp/dreamduck-fake.sock 2>&1 | tee /tmp/dreamduck-fake.log
```

终端 2：

```bash
./target/debug/robotctl --robot-socket /tmp/dreamduck-fake.sock health
./target/debug/robotctl --robot-socket /tmp/dreamduck-fake.sock health --json | tee /tmp/dreamduck-fake-health-5min.json
```

第一份状态截图记录 1,633 个 tick、50.0 Hz、0 missed。后续完整 JSON 记录如下：

| 指标 | 结果 |
|---|---|
| robot.healthy | true |
| control_loop.target_hz | 50.0 |
| control_loop.achieved_hz | 50.022486039266056 |
| control_loop.ticks | 25,826 |
| control_loop.missed | 0 |
| control_loop.last_tick_age_ms | 10 |
| bus.consecutive_errors | 0 |
| bus.startup_failures | 0 |
| CPU 温度 | 62.124 °C |
| CPU 降频等级 | 0 |
| CPU 当前/最大频率 | 2,002,000 / 2,002,000 kHz |

按 50 Hz 估算，25,826 个 tick 对应约 8 分 36 秒，超过工单要求的 5 分钟。原始查询结果保存在 [健康报告](../../artifacts/board-validation/2026-10-03-a733-health.json)。

## 日志与验证边界

运行期间日志持续出现 `intents went stale — the velocity command is zeroed`：没有控制客户端持续发送指令，deadman 检查把速度命令归零。控制循环仍被报告为健康。超时保护的机制由 [robotd-design.md](../design/robotd-design.md) 说明。

本次只运行了 `robotd`，因此 `updaterd` 和 `configd` 的 socket 不存在，健康报告显示无法连接。总线、IMU、电池和舵机温度是 FakeIo 提供的模拟值；CPU 温度和频率来自主板。本次没有加载 ONNX 策略，也没有验证飞特舵机、真实 IMU、摄像头或 NPU。

## systemd 开发服务验证

用户在主板将源码快进至 `e62f3f8`，执行 `check`、脚本测试和 `sudo sh scripts/a733-dev.sh install duck`。板卡检查及脚本测试通过，服务显示 `enabled`、`active (running)`，进程以 `duck` 用户运行。随后 `sh scripts/a733-dev.sh health --json` 得到：

| 指标 | 结果 |
|---|---|
| robot.healthy | true |
| control_loop.achieved_hz | 50.024959953768935 |
| control_loop.ticks | 21,427 |
| control_loop.missed | 0 |
| control_loop.last_tick_age_ms | 3 |
| bus.consecutive_errors / startup_failures | 0 / 0 |
| imu.ready | true（虚拟硬件） |
| CPU 温度 | 63.178 °C |
| CPU 降频等级 | 0 |

按 50 Hz 估算约运行 7 分 8 秒；[服务健康报告](../../artifacts/board-validation/2026-10-03-a733-service-health.json)保存本次 JSON。初次查询发生在第 4 个 tick，频率为 `null`、IMU 未就绪；后续查询确认统计已更新。频率和慢速传感器状态由源码中的 1 秒统计窗口更新。

首次启动日志还包含身份信息写入警告：开发服务创建独立的运行目录，现有身份发布函数却默认写 `/run/robotd/identity.json`，普通用户无法创建父目录。修正是在服务配置中设置已有的 `DUCK_RUNTIME_DIR=/run/dreamduck-a733-dev`，让该函数写入 systemd 分配给用户的目录，不修改 Rust 源码。单元生成测试先因缺少该设置而失败，再通过修正后的检查；实际身份文件写入和警告消失仍待主板复验。

## 下一阶段

基础构建、进程启动、持续运行、本地 IPC，以及 [A733 开发服务](../robot/orangepi-a733.md)的实际安装和后台运行已取得成功记录。开机启动已设置；身份目录修正、重启后的自动启动与 SSH 管理仍待主板验收。

开发入口的本地检查已通过：POSIX shell 语法检查、ShellCheck 0.11.0、设备树与架构识别测试、非 root 服务账号和操作权限测试、socket 与服务命令路由测试、`git diff --check`。测试在 Windows 的 Git Bash 中执行，用户也在主板执行了 `e62f3f8` 的脚本测试。没有修改 Rust 源码，本次未在 Windows 运行 Rust 全工作区测试；主板此前执行的是构建与运行验证。身份目录修正的实际启动和重启验收需要继续执行。

发布包的 `hooks/preinstall.in` 也会调用 GStreamer、RKAIQ 和 NPU 安装脚本，所以平台选择需要覆盖首次部署与更新两条路径；更新钩子的职责见 [updater-design.md §9.1](../design/updater-design.md#91-if-a-fresh-install-does-it-the-hook-does-it)。
