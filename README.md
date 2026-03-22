<div align="center"><a name="readme-top"></a>

# Uninstall Aliyun Service

一键卸载阿里云云安全中心（云盾）Agent 并清理历史残留组件的 Bash 脚本，<br/>
可选同时卸载云助手（Cloud Assistant）。

[English](./README.en.md) · [报告问题][github-issues-link] · [参考文档][doc-uninstall-link]

<!-- SHIELD GROUP -->

[![][github-stars-shield]][github-stars-link]
[![][github-forks-shield]][github-forks-link]
[![][github-issues-shield]][github-issues-link]
[![][github-license-shield]][github-license-link]<br/>
[![][github-contributors-shield]][github-contributors-link]
[![][github-lastcommit-shield]][github-lastcommit-link]

</div>

<details>
<summary><kbd>目录</kbd></summary>

#### TOC

- [📋 概述](#-概述)
- [⚠️ 前置条件](#️-前置条件)
- [🚀 快速开始](#-快速开始)
- [📖 用法](#-用法)
- [🔩 执行流程](#-执行流程)
- [🛠 故障排查](#-故障排查)
- [📚 参考资料](#-参考资料)
- [📝 许可证](#-许可证)

</details>

## 📋 概述

这个项目面向仍然存在历史遗留组件的 Linux 服务器环境。脚本会优先调用阿里云官方卸载脚本，并补充处理旧版 `quartz`、`aliyun-service`、`agentwatch` 等常见残留。通过 `--include-assist` 参数还可以一并卸载云助手（`assist_daemon`）。

适用场景：

- 🛡️ 需要卸载云安全中心 Agent（原 Aegis / 安骑士）
- 🧹 服务器上可能安装过旧版云盾组件，需要一并清理
- 🤖 需要卸载云助手（Cloud Assistant / `assist_daemon`）
- 📦 希望用一个脚本完成官方卸载和残留清理，而不是手动逐项操作
- 🖥️ 在非阿里云 ECS 或已退役的服务器上移除相关组件

<div align="right">

[![][back-to-top]](#readme-top)

</div>

## ⚠️ 前置条件

在执行脚本前，请确认以下条件：

1. 当前系统为 Linux
2. 使用 `root` 或具备等效 `sudo` 权限的账户执行
3. 已安装 `curl` 或 `wget`（用于下载官方卸载脚本）
4. 如果要走官方完整卸载流程，服务器需要能够访问阿里云卸载入口

> \[!IMPORTANT]
>
> 必须先在 [云安全中心控制台](https://yundun.console.aliyun.com) 关闭以下保护项，否则自保护机制会阻止卸载：
>
> - **Agent Protection**（客户端自保护）
> - **Malicious Host Behavior Prevention**（恶意主机行为防御）

<div align="right">

[![][back-to-top]](#readme-top)

</div>

## 🚀 快速开始

```bash
curl -fsSL https://raw.githubusercontent.com/babywbx/Uninstall-aliyun-service/main/UAS.sh | sudo bash
```

非交互模式（跳过确认提示）：

```bash
curl -fsSL https://raw.githubusercontent.com/babywbx/Uninstall-aliyun-service/main/UAS.sh | sudo bash -s -- -y
```

连同云助手一起卸载：

```bash
curl -fsSL https://raw.githubusercontent.com/babywbx/Uninstall-aliyun-service/main/UAS.sh | sudo bash -s -- --include-assist
```

<div align="right">

[![][back-to-top]](#readme-top)

</div>

## 📖 用法

```bash
sudo bash UAS.sh [options]
```

### 参数

| 选项 | 说明 |
| --- | --- |
| `-y`, `--yes` | 跳过确认提示，直接执行 |
| `--include-assist` | 同时卸载云助手（Cloud Assistant / `assist_daemon`） |
| `--skip-quartz` | 跳过旧版 quartz 清理 |
| `-h`, `--help` | 显示帮助信息 |

<div align="right">

[![][back-to-top]](#readme-top)

</div>

## 🔩 执行流程

脚本默认执行以下流程：

1. 检查当前用户是否具备 root 权限
2. 进行交互确认，或在 `-y` 模式下直接继续
3. 检测当前主机是阿里云 ECS 还是非 ECS 环境，选择对应的卸载入口
4. 下载并执行阿里云官方 `uninstall.sh`
5. 下载并执行旧版 `quartz_uninstall.sh`，用于兼容清理（可通过 `--skip-quartz` 跳过）
6. 终止 Agent 相关进程、停用服务、删除残留文件和目录
7. 若指定 `--include-assist`，卸载云助手（停止 `assist_daemon` → 停止服务 → 卸载软件包 → 清理目录）
8. 验证常见 Agent 进程是否仍在运行

当前版本不会主动修改防火墙规则、覆盖 `/etc/motd`，也不会创建宽权限目录。

<div align="right">

[![][back-to-top]](#readme-top)

</div>

## 🛠 故障排查

### 官方卸载脚本执行失败

如果官方脚本返回失败，优先检查云安全中心控制台中的以下保护项是否已经关闭：

- **Agent Protection**（客户端自保护）
- **Malicious Host Behavior Prevention**（恶意主机行为防御）

### 官方卸载脚本下载失败

常见原因包括：

- 服务器网络出站受限
- DNS 解析异常
- 当前环境无法访问阿里云卸载入口

脚本会尝试回退到其他入口，并继续执行本地残留清理，但这不能完全替代官方卸载流程。

### 卸载后仍有相关进程

如果脚本结束后仍然发现相关进程，通常表示自保护仍然生效，或进程尚未完全退出。建议在关闭保护项后重新执行一次。

### 卸载后立即重装失败

阿里云官方文档提到，卸载后短时间内重新安装可能存在限制，请以官方控制台和文档说明为准。

<div align="right">

[![][back-to-top]](#readme-top)

</div>

## 📚 参考资料

- [阿里云：卸载云安全中心客户端][doc-uninstall-link]
- [阿里云：安装云安全中心客户端][doc-install-link]
- [阿里云：启动、停止或卸载云助手客户端][doc-assist-link]

<div align="right">

[![][back-to-top]](#readme-top)

</div>

## 📝 许可证

Copyright © 2018-present [Babywbx][profile-link].<br/>
本项目基于 [MIT](./LICENSE) 许可证发布。

<!-- LINK GROUP -->

[back-to-top]: https://img.shields.io/badge/-BACK_TO_TOP-151515?style=flat-square
[doc-assist-link]: https://help.aliyun.com/zh/ecs/user-guide/start-stop-or-uninstall-the-cloud-assistant-agent
[doc-install-link]: https://help.aliyun.com/zh/security-center/user-guide/install-the-security-center-agent
[doc-uninstall-link]: https://help.aliyun.com/zh/security-center/user-guide/uninstall-the-security-center-agent
[github-contributors-link]: https://github.com/babywbx/Uninstall-aliyun-service/graphs/contributors
[github-contributors-shield]: https://img.shields.io/github/contributors/babywbx/Uninstall-aliyun-service?color=c4f042&labelColor=black&style=flat-square
[github-forks-link]: https://github.com/babywbx/Uninstall-aliyun-service/network/members
[github-forks-shield]: https://img.shields.io/github/forks/babywbx/Uninstall-aliyun-service?color=8ae8ff&labelColor=black&style=flat-square
[github-issues-link]: https://github.com/babywbx/Uninstall-aliyun-service/issues
[github-issues-shield]: https://img.shields.io/github/issues/babywbx/Uninstall-aliyun-service?color=ff80eb&labelColor=black&style=flat-square
[github-lastcommit-link]: https://github.com/babywbx/Uninstall-aliyun-service/commits/main
[github-lastcommit-shield]: https://img.shields.io/github/last-commit/babywbx/Uninstall-aliyun-service?labelColor=black&style=flat-square
[github-license-link]: https://github.com/babywbx/Uninstall-aliyun-service/blob/main/LICENSE
[github-license-shield]: https://img.shields.io/github/license/babywbx/Uninstall-aliyun-service?color=white&labelColor=black&style=flat-square
[github-stars-link]: https://github.com/babywbx/Uninstall-aliyun-service/stargazers
[github-stars-shield]: https://img.shields.io/github/stars/babywbx/Uninstall-aliyun-service?color=ffcb47&labelColor=black&style=flat-square
[profile-link]: https://github.com/babywbx
