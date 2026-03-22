<div align="center"><a name="readme-top"></a>

# Uninstall Aliyun Service

A Bash script to uninstall the Alibaba Cloud Security Center (YunDun) agent on Linux<br/>
and clean up legacy component leftovers, with optional Cloud Assistant removal.

[简体中文](./README.md) · [Report Issue][github-issues-link] · [Documentation][doc-uninstall-link]

<!-- SHIELD GROUP -->

[![][github-stars-shield]][github-stars-link]
[![][github-forks-shield]][github-forks-link]
[![][github-issues-shield]][github-issues-link]
[![][github-license-shield]][github-license-link]<br/>
[![][github-contributors-shield]][github-contributors-link]
[![][github-lastcommit-shield]][github-lastcommit-link]

</div>

<details>
<summary><kbd>Table of contents</kbd></summary>

#### TOC

- [📋 Overview](#-overview)
- [⚠️ Prerequisites](#️-prerequisites)
- [🚀 Quick Start](#-quick-start)
- [📖 Usage](#-usage)
- [🔩 What It Does](#-what-it-does)
- [🛠 Troubleshooting](#-troubleshooting)
- [📚 References](#-references)
- [📝 License](#-license)

</details>

## 📋 Overview

This project targets Linux hosts that may still contain historical YunDun / Aegis components. The script prefers the official Alibaba Cloud uninstall flow and adds cleanup for common legacy remnants such as `quartz`, `aliyun-service`, and `agentwatch`. With `--include-assist`, it also removes Cloud Assistant (`assist_daemon`).

Typical use cases:

- 🛡️ Remove the Security Center agent (formerly Aegis / AnQiShi)
- 🧹 Clean up older YunDun components that may still be installed on the host
- 🤖 Remove Cloud Assistant (`assist_daemon`)
- 📦 Run one script for both official uninstall and leftover cleanup instead of doing it manually
- 🖥️ Strip related components from non-ECS or decommissioned servers

<div align="right">

[![][back-to-top]](#readme-top)

</div>

## ⚠️ Prerequisites

Before running the script, make sure that:

1. The target system is Linux
2. You run it as `root` or with equivalent `sudo` privileges
3. `curl` or `wget` is installed (used to download the official uninstall scripts)
4. The host can reach Alibaba Cloud uninstall endpoints if you want the full official uninstall flow

> \[!IMPORTANT]
>
> Disable the following protections in the [Security Center console](https://yundun.console.aliyun.com) first — otherwise self-protection will block the uninstall:
>
> - **Agent Protection**
> - **Malicious Host Behavior Prevention**

<div align="right">

[![][back-to-top]](#readme-top)

</div>

## 🚀 Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/babywbx/Uninstall-aliyun-service/main/UAS.sh | sudo bash
```

Non-interactive mode (skip confirmation):

```bash
curl -fsSL https://raw.githubusercontent.com/babywbx/Uninstall-aliyun-service/main/UAS.sh | sudo bash -s -- -y
```

Also remove Cloud Assistant:

```bash
curl -fsSL https://raw.githubusercontent.com/babywbx/Uninstall-aliyun-service/main/UAS.sh | sudo bash -s -- --include-assist
```

<div align="right">

[![][back-to-top]](#readme-top)

</div>

## 📖 Usage

```bash
sudo bash UAS.sh [options]
```

### Options

| Flag | Description |
| --- | --- |
| `-y`, `--yes` | Run without confirmation |
| `--include-assist` | Also uninstall Cloud Assistant (`assist_daemon`) |
| `--skip-quartz` | Skip legacy quartz cleanup |
| `-h`, `--help` | Show help |

<div align="right">

[![][back-to-top]](#readme-top)

</div>

## 🔩 What It Does

By default, the script performs the following steps:

1. Checks whether the current user has root privileges
2. Prompts for confirmation unless `-y` is used
3. Detects whether the host is an Alibaba Cloud ECS instance or not, and picks the appropriate uninstall endpoint
4. Downloads and runs the official Alibaba Cloud `uninstall.sh`
5. Downloads and runs legacy `quartz_uninstall.sh` for compatibility cleanup (skippable with `--skip-quartz`)
6. Kills agent processes, disables services, and removes leftover files and directories
7. If `--include-assist` is specified, uninstalls Cloud Assistant (stops `assist_daemon` → stops service → removes package → cleans up directories)
8. Verifies whether common agent processes are still running

The current version does not modify firewall rules, overwrite `/etc/motd`, or create overly permissive directories.

<div align="right">

[![][back-to-top]](#readme-top)

</div>

## 🛠 Troubleshooting

### The official uninstall script fails

First verify that the following protections are disabled in the Security Center console:

- **Agent Protection**
- **Malicious Host Behavior Prevention**

### The official uninstall script cannot be downloaded

Common causes include:

- Outbound network restrictions on the server
- DNS resolution issues
- The host cannot reach Alibaba Cloud uninstall endpoints

The script will try fallback endpoints and continue with local leftover cleanup, but that does not fully replace the official uninstall flow.

### Related processes are still running after uninstall

This usually means self-protection is still active, or the processes have not fully exited yet. Disable the protection features and run the script again.

### Reinstall fails shortly after uninstall

Alibaba Cloud documentation notes that reinstalling shortly after uninstall may be restricted. Follow the current console and official documentation guidance.

<div align="right">

[![][back-to-top]](#readme-top)

</div>

## 📚 References

- [Alibaba Cloud: Uninstall the Security Center agent][doc-uninstall-link]
- [Alibaba Cloud: Install the Security Center agent][doc-install-link]
- [Alibaba Cloud: Stop and uninstall Cloud Assistant agent][doc-assist-link]

<div align="right">

[![][back-to-top]](#readme-top)

</div>

## 📝 License

Copyright © 2018-present [Babywbx][profile-link].<br/>
This project is licensed under [MIT](./LICENSE).

<!-- LINK GROUP -->

[back-to-top]: https://img.shields.io/badge/-BACK_TO_TOP-151515?style=flat-square
[doc-assist-link]: https://www.alibabacloud.com/help/en/ecs/user-guide/stop-and-uninstall-the-cloud-assistant-agent
[doc-install-link]: https://www.alibabacloud.com/help/en/security-center/user-guide/install-the-security-center-agent
[doc-uninstall-link]: https://www.alibabacloud.com/help/en/security-center/user-guide/uninstall-the-security-center-agent
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
