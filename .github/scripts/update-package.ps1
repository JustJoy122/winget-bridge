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

$latestVersion = $release.tag_name -replace '^v', ''
Write-Host "Upstream latest version: $latestVersion"

# 2. 从 Assets 中提取目标安装包的 URL
$assets = $release.assets | Where-Object { $_.name -match $AssetRegex }
if (-not $assets) {
    Write-Error "Cannot find asset matching regex: $AssetRegex"
    exit 1
}
$downloadUrls = $assets | ForEach-Object { $_.browser_download_url }
Write-Host "Installer URLs found: $($downloadUrls -join ', ')"

# 3. 获取 winget-pkgs 仓库中的当前版本
$parts = $PackageId.Split('.')
$publisher = $parts[0]
$packageName = $parts[1]
$firstLetter = $publisher.Substring(0, 1).ToLower()
$manifestPath = "$firstLetter/$publisher/$packageName"
$wingetApiUrl = "https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/$manifestPath"

try {
    $manifests = Invoke-RestMethod -Uri $wingetApiUrl -Headers $headers
    $currentVersion = $manifests | Where-Object { $_.type -eq "dir" } | Select-Object -ExpandProperty name | Sort-Object { [version]$_ } -Descending | Select-Object -First 1
} catch {
    $currentVersion = "0.0.0"
}
Write-Host "Current winget version: $currentVersion"

# 初始化结果变量
$status = "Unknown"
$prLink = ""
$newVersion = $latestVersion

# 4. 版本与查重逻辑
if ($latestVersion -eq $currentVersion) {
    Write-Host "Already up to date."
    $status = "✅ 已是最新"
    $newVersion = $currentVersion
} else {
    # 4.1 检查是否已有你提交的开放 PR
    $myUsername = $env:GITHUB_REPOSITORY_OWNER
    $searchQuery = "repo:microsoft/winget-pkgs is:pr is:open author:$myUsername $PackageId in:title"
    $searchUrl = "https://api.github.com/search/issues?q=$([uri]::EscapeDataString($searchQuery))"
    $searchResult = Invoke-RestMethod -Uri $searchUrl -Headers $headers

    if ($searchResult.total_count -gt 0) {
        Write-Host "Found existing open PR. Skipping."
        $status = "⏳ PR 等待审核"
        $prLink = $searchResult.items[0].html_url
    } else {
        # 4.2 提交新 PR
        Write-Host "New version detected! Submitting PR..."
        
        # 下载 Komac (严格匹配 x86_64)
        $komacApiUrl = "https://api.github.com/repos/russellbanks/Komac/releases/latest"
        $komacRelease = Invoke-RestMethod -Uri $komacApiUrl -Headers $headers
        $komacAsset = $komacRelease.assets | Where-Object { $_.name -match "x86_64-pc-windows-msvc\.exe$" } | Select-Object -First 1
        if (-not $komacAsset) { Write-Error "Cannot find Komac x86_64 executable."; exit 1 }
        
        Invoke-WebRequest -Uri $komacAsset.browser_download_url -OutFile komac.exe
        
        # 构建参数并执行
        $komacArgs = @("update", $PackageId, "--version", $latestVersion, "--token", $env:WINGET_TOKEN, "--submit")
        foreach ($url in $downloadUrls) {
            $komacArgs += "--urls"
            $komacArgs += $url
        }
        
        # 运行并捕获输出
        $komacOutput = & ./komac.exe $komacArgs 2>&1 | Out-String
        Write-Host $komacOutput
        
        # 获取刚刚提交的 PR 链接 (通过 API 查最新的)
        Start-Sleep -Seconds 3
        $newSearchResult = Invoke-RestMethod -Uri $searchUrl -Headers $headers
        if ($newSearchResult.total_count -gt 0) {
            $prLink = $newSearchResult.items[0].html_url
            $status = "🚀 已自动提交 PR"
        } else {
            $status = "⚠️ PR 提交可能失败"
        }
    }
}

# 5. 写入状态文件
$resultFile = "results/$($PackageId).json"
$resultData = @{
    PackageId = $PackageId
    Version = $newVersion
    Status = $status
    PRLink = $prLink
    Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
}
$resultData | ConvertTo-Json | Out-File -FilePath $resultFile -Encoding utf8
