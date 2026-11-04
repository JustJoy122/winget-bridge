# Winget Bridge

[简体中文](README_ZH.md) | **English**

A fully automated GitHub Actions bridge that keeps Microsoft WinGet packages in sync with upstream GitHub releases.

This repository acts as a centralized maintenance hub for multiple open-source Windows packages. It automatically detects upstream updates, prevents duplicate submissions, and opens Pull Requests to the official `winget-pkgs` repository.

## 📊 Automation Status Dashboard

**Last Checked:** <!-- TIMESTAMP_START -->2026-11-04 06:54:34 (UTC)<!-- TIMESTAMP_END -->

<!-- TABLE_START -->
| Package | Version | Status | PR Link |
| --- | --- | --- | --- |
| AnywhereLabs.AgentsAnywhere | 2.1.0 | ⏳ PR Pending | [View PR](https://github.com/microsoft/winget-pkgs/pull/469693) |
| AnywhereLabs.DSHDesktop | 2.0.21-next | ✅ Up to date | - |
| AstralSightStudios.AstroBox | 2.2.5 | ⏳ PR Pending | [View PR](https://github.com/microsoft/winget-pkgs/pull/467853) |
| LocalSend.LocalSend.CLI | 1.18.2 | ✅ Up to date | - |
| LocalSend.LocalSend | 1.18.2 | ✅ Up to date | - |
| luolangaga.tubatools | 1.8.1 | ✅ Up to date | - |
| Nlitesoft.NTLite | 2026.10.12522 | ✅ Up to date | - |
| Tianyu199509.DeskBox | 1.5.9 | ⏳ PR Pending | [View PR](https://github.com/microsoft/winget-pkgs/pull/459856) |

<!-- TABLE_END -->

## ✨ Core Mechanisms
- **Fully Automated:** Daily triggers using [Komac](https://github.com/russellbanks/Komac) to submit updates.
- **Duplicate Prevention:** Built-in API checks skip packages that already have an open PR, reducing moderator workload.
- **Concurrency & Isolation:** Uses GitHub Actions Matrix strategy to process multiple packages simultaneously and independently.
- **Status Write-back:** Automatically updates this README with the latest timestamp and package status, preventing repository dormancy.
- **Monorepo Architecture:** Add a single JSON entry to onboard a new software.

## 🚀 How to Add a New Package
To start tracking new software, edit the `packages.json` file in the root directory and add a new object. Example:
```json
[
  {
    "id": "Publisher.AppName",
    "repo": "Owner/Repository",
    "assetRegex": "_x64\\.exe$"
  }
]
```
- **id**: The unique Package Identifier in WinGet (e.g., `AstralSightStudios.AstroBox`).
- **repo**: The upstream GitHub repository (`Username/RepoName`).
- **assetRegex**: Regex to match the specific installer asset from the GitHub Release.

*Note: The package must already exist in the `winget-pkgs` repository (initial submission must be done manually).*

## ⚙️ Setup Requirements
1. Create a Classic Personal Access Token (PAT) with `public_repo` scope.
2. Go to **Settings -> Secrets and variables -> Actions** and create a secret named `WINGET_TOKEN`.

## 📄 License
This repository is licensed under the MIT License.
















