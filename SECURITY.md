# Security Policy

## Supported Versions

As this project is primarily an automation and synchronization tool running on GitHub Actions, we only provide security updates for the latest codebase on the `main` branch. 

| Version / Branch | Supported          |
| ---------------- | ------------------ |
| `main` (Latest)  | :white_check_mark: |
| Older commits    | :x:                |

## Reporting a Vulnerability

**Please do NOT report security vulnerabilities through public GitHub issues.**

If you discover a security vulnerability within `winget-bridge`, please report it using the **Private vulnerability reporting** feature on the [Security](https://github.com/JustJoy122/winget-bridge/security) tab of this repository.

### What to include in your report:
* A description of the vulnerability.
* Steps to reproduce the issue.
* Potential impact (e.g., unauthorized PR submission, token leakage).

### Our Response:
We will acknowledge your report within **48 hours** and provide an estimated timeline for a fix. We kindly ask you to give us a reasonable amount of time to resolve the issue before making any information public.

### Security Scope for this Project:
Since this project generates and submits manifests to the official `microsoft/winget-pkgs` repository, we are particularly concerned with:
1. **Token Security:** Any vulnerability that could expose the `WINGET_TOKEN` or allow unauthorized actions on behalf of the repository owner.
2. **Supply Chain Attacks:** Any bypasses in our URL validation or Regex matching that could lead to a malicious installer URL being submitted to WinGet.
3. **Script Injection:** Vulnerabilities in the PowerShell scripts allowing arbitrary code execution in the GitHub Actions environment.

---
---

# 安全政策 (Security Policy)

## 支持的版本

由于本项目主要是一个运行在 GitHub Actions 上的自动化和同步工具，我们仅为 `main` 分支上的最新代码库提供安全更新。

| 版本 / 分支 | 支持状态 |
| ---------------- | ---------------- |
| `main` (最新代码) | :white_check_mark: |
| 历史 Commit      | :x:              |

## 报告漏洞

**请绝对不要通过 GitHub 公开的 Issues 报告安全漏洞。**

如果您在 `winget-bridge` 中发现了安全漏洞，请使用本仓库 [Security](https://github.com/JustJoy122/winget-bridge/security) 选项卡下的 **“私密漏洞报告 (Private vulnerability reporting)”** 功能进行报告。

### 报告中需要包含：
* 漏洞的详细描述。
* 复现该问题的步骤。
* 潜在的影响（例如：未经授权的 PR 提交、Token 泄露等）。

### 我们的反馈：
我们将在 **48 小时内** 确认您的报告，并给出修复的预估时间。在问题解决并公开之前，我们恳请您给予我们合理的修复时间。

### 本项目的安全范围：
由于本项目会生成清单并提交到官方的 `microsoft/winget-pkgs` 仓库，我们特别关注以下类型的安全问题：
1. **Token 安全**：任何可能导致 `WINGET_TOKEN` 泄露，或允许恶意用户代替仓库所有者执行操作的漏洞。
2. **供应链攻击**：任何可以绕过 URL 验证或正则匹配规则，从而导致恶意安装包链接被提交到 WinGet 的漏洞。
3. **脚本注入**：PowerShell 脚本中可能导致 GitHub Actions 运行环境被任意代码执行的安全隐患。
