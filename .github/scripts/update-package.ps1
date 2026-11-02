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

# 3. 获取 winget-pkgs 仓库中的所有版本文件夹
$parts = $PackageId.Split('.')
$publisher = $parts[0]
$packageName = $parts[1]
$firstLetter = $publisher.Substring(0, 1).ToLower()
$manifestPath = "$firstLetter/$publisher/$packageName"
$wingetApiUrl = "https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/$manifestPath"

$existingVersions = @()
try {
    $manifests = Invoke-RestMethod -Uri $wingetApiUrl -Headers $headers
    # 不排序，直接取出所有版本文件夹的名字
    $existingVersions = $manifests | Where-Object { $_.type -eq "dir" } | Select-Object -ExpandProperty name
} catch {
    Write-Host "Package manifest directory not found (may be a brand new package)."
}

# 检查上游的最新版本是否已经存在于主仓库中
$isUpToDate = $existingVersions -contains $latestVersion

# 初始化结果变量
$status = "Unknown"
$prLink = ""
$newVersion = $latestVersion

# 4. 查重与提交逻辑
if ($isUpToDate) {
    Write-Host "Already up to date. Found version $latestVersion in winget-pkgs."
    $status = "✅ 已是最新"
    # 随便取一个最新的版本号用于展示
    $newVersion = $existingVersions | Select-Object -Last 1 
} else {
    Write-Host "Version $latestVersion not found in winget-pkgs. Checking for open PRs..."
    
    # 4.1 检查是否已有开放 PR (搜索整个仓库，不限制作者，放宽搜索词)
    $searchQuery = "repo:microsoft/winget-pkgs is:pr is:open $PackageId"
    $searchUrl = "https://api.github.com/search/issues?q=$([uri]::EscapeDataString($searchQuery))"
    $searchResult = Invoke-RestMethod -Uri $searchUrl -Headers $headers

    # 过滤出真正包含 PackageId 的 PR (防止搜出一堆无关的 PR)
    $validPr = $searchResult.items | Where-Object { $_.title -match [regex]::Escape($PackageId) } | Select-Object -First 1

    if ($validPr) {
        Write-Host "Found existing open PR. Skipping."
        $status = "⏳ PR 等待审核"
        $prLink = $validPr.html_url
        $newVersion = "Pending"
    } else {
        # 4.2 提交新 PR
        Write-Host "No open PRs found. Submitting new PR..."
        
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
        
        $komacOutput = & ./komac.exe $komacArgs 2>&1 | Out-String
        Write-Host $komacOutput
        
        # 获取刚刚提交的 PR 链接
        Start-Sleep -Seconds 5
        $newSearchResult = Invoke-RestMethod -Uri $searchUrl -Headers $headers
        $newValidPr = $newSearchResult.items | Where-Object { $_.title -match [regex]::Escape($PackageId) } | Select-Object -First 1
        
        if ($newValidPr) {
            $prLink = $newValidPr.html_url
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

# 加入状态比对逻辑，防止高频轮询时产生无意义的 Commit
if (Test-Path $resultFile) {
    $oldData = Get-Content $resultFile -Raw | ConvertFrom-Json
    if ($oldData.Version -eq $resultData.Version -and $oldData.Status -eq $resultData.Status) {
        Write-Host "State unchanged. Skipping status file update."
        exit 0
    }
}

$resultData | ConvertTo-Json | Out-File -FilePath $resultFile -Encoding utf8
