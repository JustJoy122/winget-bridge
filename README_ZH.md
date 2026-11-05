# Winget Bridge (中继站)

**简体中文** | [English](README.md)

一个全自动化的 GitHub Actions 桥接仓库，旨在将上游 GitHub 发布同步到 Microsoft WinGet 包仓库。

本项目作为一个集中管理多个开源 Windows 软件更新的中继站。你不再需要每次开发者发布新版本时手动提交 WinGet 清单，本仓库会自动检测更新、防重复提交，并向主仓库发起 Pull Request。

## 📊 自动化状态面板

**最后检查时间：** <!-- TIMESTAMP_START -->2026-11-05 16:38:28 (UTC)<!-- TIMESTAMP_END -->

<!-- TABLE_START -->
| 软件包 | 版本 | 状态 | PR 链接 |
| --- | --- | --- | --- |
| AnywhereLabs.AgentsAnywhere | 2.1.0 | ⏳ PR 等待审核 | [查看 PR](https://github.com/microsoft/winget-pkgs/pull/469693) |
| AnywhereLabs.DSHDesktop | 2.0.22-next | ✅ 已是最新 | - |
| AstralSightStudios.AstroBox | 2.2.5 | ⏳ PR 等待审核 | [查看 PR](https://github.com/microsoft/winget-pkgs/pull/467853) |
| LocalSend.LocalSend.CLI | 1.18.2 | ✅ 已是最新 | - |
| LocalSend.LocalSend | 1.18.2 | ✅ 已是最新 | - |
| luolangaga.tubatools | 1.8.1 | ✅ 已是最新 | - |
| Nlitesoft.NTLite | 2026.10.12522 | ✅ 已是最新 | - |
| Tianyu199509.DeskBox | 1.5.9 | ⏳ PR 等待审核 | [查看 PR](https://github.com/microsoft/winget-pkgs/pull/459856) |

<!-- TABLE_END -->

## ✨ 核心机制
- **全自动闭环：** 每日定时触发，利用 [Komac](https://github.com/russellbanks/Komac) 自动提交更新。
- **防重复提交：** 内置智能查重逻辑，若该包已有处于 Open 状态的 PR，将自动跳过，避免骚扰审核员。
- **并发与隔离：** 使用 GitHub Actions Matrix 策略，多包同时独立处理，互不干扰。
- **状态自动回写：** 运行结束后，自动将最新时间戳和包状态更新至本 README，同时防止仓库触发 60 天休眠。
- **单仓库架构：** 只需在 JSON 配置中添加一行，即可纳管新软件。

## 🚀 如何添加新的追踪包
要开始追踪新软件，请编辑根目录下的 `packages.json` 文件，并在数组中添加新对象。写法如下：
```json
[
  {
    "id": "Publisher.AppName",
    "repo": "Owner/Repository",
    "assetRegex": "_x64\\.exe$"
  }
]
```
- **id**: 在 WinGet 中的唯一包标识符（如 `AstralSightStudios.AstroBox`）。
- **repo**: 上游 GitHub 仓库地址（`用户名/仓库名`）。
- **assetRegex**: 匹配 GitHub Release 资产的正则表达式。

*注意：该包必须已经存在于 `winget-pkgs` 主仓库中（首次提交需手动完成）。*

## ⚙️ 配置要求
1. 创建一个带有 `public_repo` 权限的 Classic PAT。
2. 在仓库 **Settings -> Secrets and variables -> Actions** 中新建名为 `WINGET_TOKEN` 的 Secret。

## 📄 开源协议
本仓库基于 MIT License 开源。






















