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

# 2. 从 Assets 中提取目标安装包的 URL
$asset = $release.assets | Where-Object { $_.name -match $AssetRegex } | Select-Object -First 1
if (-not $asset) {
    Write-Error "Cannot find asset matching regex: $AssetRegex"
    exit 1
}
$downloadUrl = $asset.browser_download_url
Write-Host "Installer URL: $downloadUrl"

# 3. 获取 winget-pkgs 仓库中的当前版本
$manifestPath = $PackageId.Split('.')[0].ToLower() + "/" + $PackageId.Split('.')[1]
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
Invoke-WebRequest -Uri "https://github.com/russellbanks/Komac/releases/latest/download/komac-x86_64-pc-windows-msvc.exe" -OutFile komac.exe

# 调用 Komac
./komac.exe update $PackageId `
    --version $latestVersion `
    --urls $downloadUrl `
    --token $env:WINGET_TOKEN `
    --submit
