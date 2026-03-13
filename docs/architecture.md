# Architecture Overview

OpenClaw Auto Heal 采用分层自愈结构，把“守护进程、健康检查、官方修复、AI 修复”串成一个最小闭环。

## 1. launchd 守护层

`launchd` 负责最底层的进程守护：

- OpenClaw Gateway 异常退出后自动拉起
- 负责系统启动后的自动加载
- 提供最基础的可用性保障

这一层解决的是“进程挂了怎么办”。

## 2. Health Check 检测层

`health-check.sh` 负责周期性检测：

- 调用 `openclaw status`
- 维护失败计数
- 连续失败达到阈值后发送通知
- 触发 `auto-heal-ai.sh`

这一层解决的是“服务虽然还在，但其实已经不健康怎么办”。

## 3. Official Doctor 修复层

在进入 AI 修复之前，`auto-heal-ai.sh` 会优先尝试官方提供的修复链路：

```bash
openclaw doctor --fix
```

这一层的意义是：

- 优先复用 OpenClaw 官方维护的修复逻辑
- 降低脚本对内部配置细节的耦合
- 在 OpenClaw 升级后更容易跟随官方修复能力演进

如果官方修复后配置验证通过、Gateway 恢复正常，则整个流程在这一层结束。

## 4. AI Auto Heal 修复层

当官方修复链路不能恢复时，才进入 AI 修复流程：

1. 检查是否已有安全备份
2. 检查当前配置 JSON 是否损坏
3. 优先尝试 `openclaw doctor --fix`
4. 检测 AI 配置来源
5. 收集 OpenClaw 配置校验错误
6. 调用 AI 生成最小修复脚本
7. 对修复脚本做安全检查
8. 执行修复脚本
9. 输出 diff（可选）
10. 验证配置
11. 更新安全备份
12. 重启 Gateway 并再次验证

这一层解决的是“当官方修复还不够时，怎么补最后一刀”。

## 配置来源策略

AI 修复层当前支持两种配置来源：

### 模式 A：独立 AI 配置
优先读取环境变量：

- `AUTO_HEAL_API_KEY`
- `AUTO_HEAL_API_ENDPOINT`
- `AUTO_HEAL_MODEL`
- `AUTO_HEAL_PROVIDER`

### 模式 B：继承 OpenClaw 配置
如果没有独立配置，则回退到：

- `models.defaultProvider`
- `models.providers.<provider>.apiKey`
- `models.providers.<provider>.endpoint`
- `models.providers.<provider>.model`

## 数据流

```text
launchd
  ↓
Gateway 运行
  ↓
health-check.sh 周期检测
  ↓
连续失败达到阈值
  ↓
auto-heal-ai.sh
  ├─ 读取安全备份 / 当前配置
  ├─ 尝试官方 doctor --fix
  ├─ 若失败，再进入 AI 修复
  ├─ 收集校验错误
  ├─ 调用 AI 生成修复脚本
  ├─ 安全校验
  ├─ 执行修复
  ├─ diff / 再次验证
  └─ 重启 Gateway
```

## 当前设计取舍

这个项目目前的设计目标不是“大而全”，而是：

- 尽量简单
- 尽量可读
- 尽量容易本地部署
- 先把单机自愈闭环做通

因此它当前更像一个：

- 运维自动化原型
- 自愈式脚手架
- 可继续工程化的开源雏形

## 后续架构演进方向

如果后续继续打磨，推荐的演进路线是：

1. 增加 dry-run 和 diff
2. 把脚本主流程拆成阶段函数
3. 增加安装脚本 / 模板生成器
4. 增加测试样例和故障注入
5. 视情况再考虑跨平台支持
