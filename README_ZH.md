# Winget Bridge (中继站)

**简体中文** | [English](README.md)

一个自动化的 GitHub Actions 桥接仓库，使用 [Komac](https://github.com/russellbanks/Komac) 将上游 GitHub 发布同步到 Microsoft WinGet 包仓库。

本项目作为一个集中管理多个开源 Windows 软件更新的中继站。你不再需要每次开发者发布新版本时手动创建和提交 WinGet 清单，本仓库会自动检测上游更新，并向 [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs) 仓库发起 Pull Request。

## ✨ 核心特性
- **全自动流程：** 每日自动检查更新，并向 `winget-pkgs` 自动提交 PR。
- **单仓库架构 (Monorepo)：** 集中管理所有追踪的软件包。
- **矩阵并发策略：** 多个包同时独立处理，互不干扰。
- **配置驱动：** 添加新包只需在 JSON 配置中加一行，无需改动核心代码。

## 🚀 如何添加新的追踪包
要开始追踪新软件，只需编辑根目录下的 `packages.json` 文件，并在数组中添加新对象：
```json
[
  {
    "id": "Publisher.AppName",
    "repo": "Owner/Repository",
    "assetRegex": "_x64\\.exe$"
  }
]
```
- **id**: 在 WinGet 中的唯一包标识符（例如 `AstralSightStudios.AstroBox`）。
- **repo**: 上游 GitHub 仓库地址（`用户名/仓库名`）。
- **assetRegex**: 用于匹配 GitHub Release 中特定安装包文件名的正则表达式。

*注意：该包必须已经存在于 `winget-pkgs` 主仓库中（首次提交必须手动完成）。*

## ⚙️ 配置要求
1. 在 GitHub 上创建一个带有 `public_repo` 权限的 Classic Personal Access Token (经典 PAT)。
2. 进入本仓库的 **Settings -> Secrets and variables -> Actions**。
3. 新建一个名为 `WINGET_TOKEN` 的 Secret，填入你的 Token。

## 📄 开源协议
本仓库基于 MIT License 开源。
