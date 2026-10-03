# 香橙派 A733 开发调试

当前支持 Orange Pi Zero 3W（设备树为 `xunlong,orangepi-zero3w`、`arm,sun60iw2p1`）上的原生 ARM64 构建和虚拟硬件开发服务。已测环境和运行数据见 [A733 验证记录](../project/a733-bringup.md)。

服务固定使用 `--fake --no-policy`，运行控制循环和本地 IPC。飞特舵机、实际 IMU、摄像头、NPU 和 ONNX 策略加载仍需后续适配。此入口不会调用 Rockchip overlay、RKAIQ、RKNN、MPP 或网络配置脚本。

这是从源码启动的独立开发服务；正式发布和更新仍由 [更新机制](../design/updater-design.md) 管理，A733 的正式安装与更新配置尚未适配。

## 准备与源码传输

主板使用 Armbian / Debian 13 ARM64，安装 C 编译工具与 Rust 1.99 或更高版本。对于本文只构建的两个程序：

```bash
sudo apt-get update
sudo apt-get install -y build-essential pkg-config ca-certificates git
source "$HOME/.cargo/env"
rustc --version
cargo --version
```

上述命令假定已经安装 Rust。全工作区构建所需的额外系统库见 [CONTRIBUTING.md](../../CONTRIBUTING.md)。`--no-policy` 不加载 ONNX Runtime；本文没有验证其安装或推理性能。

Windows 编辑并提交到 `codex/orangepi-a733` 后，通过 GitHub 管理版本。如果主板 HTTPS 连接不稳定，用 Git bundle 经 SCP 传输。首次完整 bundle：

```powershell
git bundle create artifacts/source-sync/dreamduck-a733.bundle codex/orangepi-a733
scp artifacts/source-sync/dreamduck-a733.bundle duck@192.168.10.216:/home/duck/
```

主板首次克隆：

```bash
git clone --branch codex/orangepi-a733 ~/dreamduck-a733.bundle ~/dreamduck-work
cd ~/dreamduck-work
git remote set-url origin https://github.com/serendipityshe/Dreamduck.git
git rev-parse HEAD
```

后续仍从 Windows 生成并传输 bundle；在已有目录中更新，保留编译缓存：

```bash
cd ~/dreamduck-work
git status --short
git fetch ~/dreamduck-a733.bundle codex/orangepi-a733
git merge --ff-only FETCH_HEAD
git rev-parse HEAD
```

先提交或保存本机改动再更新。bundle 只包含已提交的内容；增量 bundle 还要求主板拥有对应的基线提交。

## 构建与安装

在主板 `~/dreamduck-work` 中执行：

```bash
cargo build --locked -p robotd -p robotctl -j 2
sh scripts/a733-dev.sh check
sh scripts/a733-dev-test.sh
sh scripts/a733-dev.sh unit duck
sudo sh scripts/a733-dev.sh install duck
```

安装命令检查 Linux、aarch64 和设备树，写入 `/etc/systemd/system/dreamduck-a733-dev.service`，启用开机启动并重启服务。源码目录路径限于英文字母、数字、下划线、斜线、点和连字符；安装前可用 `unit` 查看完整配置。

进程以 `duck` 用户运行，直接使用源码目录的 `target/debug/robotd` 和 [开发参数](../../deploy/robotd-a733-dev.toml)。socket 为 `/run/dreamduck-a733-dev/robotd.sock`，服务名为 `dreamduck-a733-dev.service`。请保留源码目录和编译产物；重新编译后需重启服务才能运行新程序。参数与控制循环的含义见 [robotd-design.md](../design/robotd-design.md)。

## 常用命令

```bash
sh scripts/a733-dev.sh status
sh scripts/a733-dev.sh health --json
sh scripts/a733-dev.sh logs
sh scripts/a733-dev.sh logs -f
sudo sh scripts/a733-dev.sh stop
sudo sh scripts/a733-dev.sh start
sudo sh scripts/a733-dev.sh restart
```

`logs -f` 持续显示日志，按 Ctrl+C 结束查看。前台测试的旧 `robotd` 也可按 Ctrl+C 停止。健康查询仅连接这个开发服务；`updaterd`、`configd` 未部署时，软件栏仍会提示它们不可达。闲置时 `intents went stale` 的解释见 [验证记录](../project/a733-bringup.md#日志与验证边界)。

取消自动启动并停止开发服务：

```bash
sudo sh scripts/a733-dev.sh disable
```

## 重启验收

先确认状态为 `active (running)`，健康 JSON 中 `robot.healthy=true`。持续运行至少 5 分钟后保存结果：

```bash
sh scripts/a733-dev.sh health --json | tee /tmp/dreamduck-a733-service-health.json
sudo reboot
```

重启会断开当前 SSH 连接。稍后从 Windows 重新连接，再检查：

```powershell
ssh duck@192.168.10.216
```

```bash
cd ~/dreamduck-work
git rev-parse HEAD
systemctl is-enabled dreamduck-a733-dev.service
sh scripts/a733-dev.sh status
sh scripts/a733-dev.sh health --json
journalctl -b -u dreamduck-a733-dev.service --no-pager -n 60
```

验收需记录：SSH 可重新登录、服务为 `enabled` 且 `active (running)`、虚拟机器人健康、频率接近 50 Hz、missed 计数和本次启动日志。安装、重启和硬件功能尚未完成的检查应保持为待验收，不能由此前前台运行的结果代替。
