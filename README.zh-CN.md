# OpenClaw Auto Heal

一个为 OpenClaw Gateway 提供**自愈能力**的开源原型：当配置损坏、启动失败、健康检查连续异常时，系统会优先尝试官方 `openclaw doctor --fix`，必要时再进入 AI 修复链路，最终尽量实现自动恢复。

> English README: [README.md](./README.md)

## 项目定位

这是一个面向个人部署和小团队场景的**实验性开源项目**，目标不是替代专业运维平台，而是为 OpenClaw Gateway 提供一个轻量、可理解、可扩展的自恢复闭环。

## 当前特性

- `launchd` 守护 + 健康检查 + 官方修复 + AI 修复的分层闭环
- JSON 损坏时支持安全备份恢复
- 独立 AI 修复配置优先，OpenClaw 模型配置兜底
- 自动发现 `openclaw / curl / jq / python3` 等命令路径
- AI 修复脚本支持规则校验 + AST 校验
- 修复脚本只允许操作目标 `openclaw.json`
- 支持 `DRY_RUN=1` 预演模式
- 支持修复前后 diff 输出
- 提供 `install.sh` 一键安装脚本

## 支持平台

### 当前支持

- **macOS**
- 使用 `launchd` 的 OpenClaw Gateway 运行环境

### 暂未正式支持

- Linux
- Windows
- 非 `launchd` 服务管理环境
- 多节点或集群部署

当前版本是一个**明确的 macOS-first 项目**。

## 前置条件

安装前建议确认：

- 已安装 OpenClaw，且命令在 PATH 中可用
- 已安装 `python3`
- 已安装 `curl`
- 已安装 `jq`
- 系统可用 `launchctl`
- 已有可用的 OpenClaw 配置，或已准备独立 AI 修复配置

## 仓库结构

```text
openclaw-auto-heal/
├── .gitignore
├── LICENSE
├── README.md
├── README.zh-CN.md
├── bootstrap.sh
├── install.sh
├── docs/
│   ├── architecture.md
│   ├── architecture-diagram.md
│   └── security.md
├── launchd/
│   ├── com.openclaw.gateway.plist
│   └── com.openclaw.healthcheck.plist
└── scripts/
    ├── auto-heal-ai.sh
    └── health-check.sh
```

## 修复优先级

当前修复链路按这个顺序执行：

1. JSON 完全损坏 → 直接从安全备份恢复
2. JSON 可读取 → 优先执行官方修复：`openclaw doctor --fix`
3. 官方修复未恢复 → 再进入 AI 修复链路

这意味着 AI 现在是增强层，而不是唯一修复依赖。

## AI 配置策略

### 模式 A：独立 AI 配置（优先）

如果设置了这些环境变量，脚本优先使用它们：

```bash
export AUTO_HEAL_API_KEY="your-key"
export AUTO_HEAL_API_ENDPOINT="https://your-api-endpoint.example/v1/messages"
export AUTO_HEAL_MODEL="your-model-name"
export AUTO_HEAL_PROVIDER="external"
```

### 模式 B：继承 OpenClaw 配置（兜底）

如果没有独立配置，则回退到 OpenClaw 的模型配置。

## 安装

```bash
chmod +x install.sh bootstrap.sh
./install.sh
```

安装脚本会自动：

- 拷贝脚本到 `~/.openclaw/scripts/`
- 初始化日志目录
- 尝试创建安全备份
- 自动替换 `launchd` 模板里的用户名
- 加载 LaunchAgents

## 安装后验证

```bash
launchctl list | grep openclaw
bash ~/.openclaw/scripts/health-check.sh
DRY_RUN=1 bash ~/.openclaw/scripts/auto-heal-ai.sh
```

也可以查看日志：

```bash
tail -50 ~/.openclaw/logs/healthcheck.log
tail -50 ~/.openclaw/logs/auto-heal.log
```

## Dry Run

```bash
DRY_RUN=1 bash ~/.openclaw/scripts/auto-heal-ai.sh
```

## 卸载

```bash
launchctl unload ~/Library/LaunchAgents/com.openclaw.gateway.plist || true
launchctl unload ~/Library/LaunchAgents/com.openclaw.healthcheck.plist || true
rm -f ~/Library/LaunchAgents/com.openclaw.gateway.plist
rm -f ~/Library/LaunchAgents/com.openclaw.healthcheck.plist
rm -f ~/.openclaw/scripts/auto-heal-ai.sh
rm -f ~/.openclaw/scripts/health-check.sh
```

日志和安全备份默认不会删除，避免误删排障数据。

## 文档

- 架构说明：[`docs/architecture.md`](./docs/architecture.md)
- 架构图：[`docs/architecture-diagram.md`](./docs/architecture-diagram.md)
- 安全说明：[`docs/security.md`](./docs/security.md)

## 当前状态

我认为这个项目现在已经可以公开放到 GitHub 进行迭代，但仍建议以：

- experimental
- public prototype
- early-stage project

这样的姿态发布。

## License

MIT
