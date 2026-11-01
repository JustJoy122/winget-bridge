# Winget Bridge

[简体中文](README_ZH.md) | **English**

An automated GitHub Actions bridge that keeps Microsoft WinGet packages in sync with upstream GitHub releases using [Komac](https://github.com/russellbanks/Komac). 

This repository acts as a centralized maintenance hub for multiple open-source Windows packages. Instead of manually creating and submitting WinGet manifests every time a developer releases a new version, this bridge detects upstream updates and automatically opens a Pull Request to the [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs) repository.

## ✨ Features
- **Fully Automated:** Checks for updates daily and submits PRs to `winget-pkgs` automatically.
- **Single Repository (Monorepo):** Manage all your tracked packages in one place.
- **Matrix Strategy:** Processes multiple packages concurrently without code duplication.
- **Configuration-Driven:** Adding a new package requires only a single JSON entry, no code changes needed.

## 🚀 How to Add a New Package
To start tracking a new software, simply edit the `packages.json` file in the root directory and add a new object to the array:
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
- **assetRegex**: A regular expression to match the specific installer asset from the GitHub Release.

*Note: The package must already exist in the `winget-pkgs` repository (initial submission must be done manually).*

## ⚙️ Setup Requirements
1. Create a Personal Access Token (Classic) on GitHub with `public_repo` scope.
2. Go to **Settings -> Secrets and variables -> Actions** in this repository.
3. Create a new secret named `WINGET_TOKEN` and paste your token.

## 📄 License
This repository is licensed under the MIT License.
