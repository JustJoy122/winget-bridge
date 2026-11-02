param (
    [string]$PackageId,
    [string]$TargetRepo,
    [string]$AssetRegex
)

$ErrorActionPreference = "Stop"

Write-Host "Checking updates for: $PackageId"

# 1. 获取上游最新 Release
$headers = @{
    "Authorization" = "Bearer $env:WINGET_TOKEN"
    "User-Agent" = "Winget-Bridge-Action"
}
$releaseUrl = "https://api.github.com/repos/$TargetRepo/releases/latest"
$release = Invoke-RestMethod -Uri $releaseUrl -Headers $headers

$latestVersion = $release.tag_name -replace '^v', '' # 去除开头的 'v'
Write-Host "Upstream latest version: $latestVersion"

# 2. 从 Assets 中提取目标安装包的 URL（支持多架构）
$assets = $release.assets | Where-Object { $_.name -match $AssetRegex }
if (-not $assets) {
    Write-Error "Cannot find asset matching regex: $AssetRegex"
    exit 1
}

# 将所有匹配的 URL 用逗号拼接起来
$downloadUrls = ($assets | ForEach-Object { $_.browser_download_url }) -join ","
Write-Host "Installer URLs: $downloadUrls"

# 3. 获取 winget-pkgs 仓库中的当前版本
$parts = $PackageId.Split('.')
$publisher = $parts[0]
$packageName = $parts[1]
# 获取发布者的首字母并转小写，这是 winget-pkgs 的目录规范
$firstLetter = $publisher.Substring(0, 1).ToLower()

$manifestPath = "$firstLetter/$publisher/$packageName"
$wingetApiUrl = "https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/$manifestPath"

try {
    $manifests = Invoke-RestMethod -Uri $wingetApiUrl -Headers $headers
    # 过滤出版本文件夹，按版本号排序取最大值
    $currentVersion = $manifests | Where-Object { $_.type -eq "dir" } | Select-Object -ExpandProperty name | Sort-Object { [version]$_ } -Descending | Select-Object -First 1
} catch {
    Write-Host "Package not found in winget-pkgs yet. Assuming initial release."
    $currentVersion = "0.0.0"
}

Write-Host "Current winget version: $currentVersion"

# 4. 比对版本
if ($latestVersion -eq $currentVersion) {
    Write-Host "Already up to date. Exiting."
    exit 0
}

if ($currentVersion -eq "0.0.0") {
    Write-Host "Package not found in winget-pkgs (PR likely still pending). Exiting gracefully."
    exit 0
}

# 5. 下载 Komac 并提交更新
Write-Host "New version detected! Submitting PR..."

# 通过 API 获取 Komac 最新版的真实下载链接
$komacApiUrl = "https://api.github.com/repos/russellbanks/Komac/releases/latest"
$komacRelease = Invoke-RestMethod -Uri $komacApiUrl -Headers @{ "User-Agent" = "Winget-Bridge-Action" }

# 注意这里：严格匹配 x86_64，过滤掉 aarch64 (ARM64) 和 i686 (32位)
$komacAsset = $komacRelease.assets | Where-Object { $_.name -match "x86_64-pc-windows-msvc\.exe$" } | Select-Object -First 1

if (-not $komacAsset) {
    Write-Error "Cannot find Komac x86_64 executable."
    exit 1
}

$komacUrl = $komacAsset.browser_download_url
Write-Host "Downloading Komac from: $komacUrl"
Invoke-WebRequest -Uri $komacUrl -OutFile komac.exe

# 调用 Komac
Write-Host "Running Komac update..."
./komac.exe update $PackageId `
    --version $latestVersion `
    --urls "$downloadUrls" `
    --token $env:WINGET_TOKEN `
    --submit
