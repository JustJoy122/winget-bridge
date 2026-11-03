param (
    [string]$PackageId,
    [string]$Type,          # 新增：类型 (github 或 fixed_url)
    [string]$TargetRepo,    # 用于 github 类型
    [string]$AssetRegex,    # 用于 github 类型
    [string]$Urls           # 用于 fixed_url 类型 (逗号分隔的带架构链接，如: "url1|x64,url2|x86")
)

$ErrorActionPreference = "Stop"
Write-Host "Checking updates for: $PackageId (Type: $Type)"

$headers = @{
    "Authorization" = "Bearer $env:WINGET_TOKEN"
    "User-Agent" = "Winget-Bridge-Action"
}

$latestVersion = ""
$downloadUrls = @()

# ==========================================
# 1 & 2. 获取上游最新版本与下载链接
# ==========================================
if ($Type -eq "github") {
    # --- GitHub 获取逻辑 ---
    $releaseUrl = "https://api.github.com/repos/$TargetRepo/releases/latest"
    $release = Invoke-RestMethod -Uri $releaseUrl -Headers $headers

    $latestVersion = $release.tag_name -replace '^v', ''
    Write-Host "Upstream latest version: $latestVersion"

    $assets = $release.assets | Where-Object { $_.name -match $AssetRegex }
    if (-not $assets) {
        Write-Error "Cannot find asset matching regex: $AssetRegex"
        exit 1
    }
    
    foreach ($asset in $assets) {
        # 智能推断架构
        $arch = "x64"
        if ($asset.name -match "arm64|aarch64") { $arch = "arm64" }
        elseif ($asset.name -match "x86|ia32|32bit") { $arch = "x86" }
        
        $downloadUrls += "$($asset.browser_download_url)|$arch"
    }
} elseif ($Type -eq "fixed_url") {
    # --- 固定 URL 获取逻辑 ---
    $urlArray = $Urls.Split(",")
    $downloadUrls = $urlArray
    
    # 下载第一个链接（通常是 x64）来读取真实版本号
    $firstUrl = $urlArray[0].Split("|")[0]
    $tempFile = "temp_setup.exe"
    Write-Host "Downloading fixed URL to extract version: $firstUrl"
    Invoke-WebRequest -Uri $firstUrl -OutFile $tempFile
    
    # 读取 exe 内部的产品版本号
    $exeVersion = (Get-Item $tempFile).VersionInfo.ProductVersion
    if (-not $exeVersion) {
        Write-Error "Failed to extract version from fixed URL executable."
        exit 1
    }
    
    # 清理版本号字符串（有些会带逗号或多余空格，如 "1, 2, 3" 转为 "1.2.3"）
    $latestVersion = $exeVersion -replace ',', '.' -replace ' ', ''
    Write-Host "Upstream latest version (extracted from EXE): $latestVersion"
    Remove-Item $tempFile -Force
} else {
    Write-Error "Unknown Type: $Type"
    exit 1
}

Write-Host "Installer URLs: $($downloadUrls -join ', ')"

# ==========================================
# 3. 获取 winget-pkgs 仓库中的当前版本
# ==========================================
$parts = $PackageId.Split('.')
$publisher = $parts[0]
$packageName = $parts[1]
$firstLetter = $publisher.Substring(0, 1).ToLower()
$manifestPath = "$firstLetter/$publisher/$packageName"
$wingetApiUrl = "https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/$manifestPath"

$existingVersions = @()
try {
    $manifests = Invoke-RestMethod -Uri $wingetApiUrl -Headers $headers
    $existingVersions = $manifests | Where-Object { $_.type -eq "dir" } | Select-Object -ExpandProperty name
} catch {
    Write-Host "Package manifest directory not found (may be a brand new package)."
}

$latestInWinget = "0.0.0"
if ($existingVersions.Count -gt 0) {
    $latestInWinget = $existingVersions | Sort-Object { 
        try {
            $vStr = $_ -replace '[^0-9\.]', ''
            if ($vStr) { [version]$vStr } else { [version]'0.0.0' }
        } catch { [version]'0.0.0' }
    } -Descending | Select-Object -First 1
}

$isUpToDate = $existingVersions -contains $latestVersion

# ==========================================
# 4. 查重与提交逻辑
# ==========================================
$status = "Unknown"
$prLink = ""
$newVersion = $latestVersion

if ($isUpToDate) {
    Write-Host "Already up to date. Found version $latestVersion in winget-pkgs."
    $status = "✅ 已是最新"
    $newVersion = $latestInWinget 
} else {
    Write-Host "Version $latestVersion not found in winget-pkgs. Checking for open PRs..."
    
    # 4.1 检查是否已有任何人的开放 PR
    $searchQuery = "repo:microsoft/winget-pkgs is:pr is:open $PackageId"
    $searchUrl = "https://api.github.com/search/issues?q=$([uri]::EscapeDataString($searchQuery))"
    $searchResult = Invoke-RestMethod -Uri $searchUrl -Headers $headers

    $validPr = $searchResult.items | Where-Object { $_.title -match [regex]::Escape($PackageId) } | Select-Object -First 1

    if ($validPr) {
        Write-Host "Found existing open PR. Skipping."
        $status = "⏳ PR 等待审核"
        $prLink = $validPr.html_url
    } else {
        Write-Host "No open PRs found. Submitting new PR..."
        
        # 下载 Komac (严格匹配 x86_64)
        $komacApiUrl = "https://api.github.com/repos/russellbanks/Komac/releases/latest"
        $komacRelease = Invoke-RestMethod -Uri $komacApiUrl -Headers $headers
        $komacAsset = $komacRelease.assets | Where-Object { $_.name -match "x86_64-pc-windows-msvc\.exe$" } | Select-Object -First 1
        if (-not $komacAsset) { Write-Error "Cannot find Komac x86_64 executable."; exit 1 }
        
        Invoke-WebRequest -Uri $komacAsset.browser_download_url -OutFile komac.exe
        
        # 构建参数并执行
        $komacArgs = @("update", $PackageId, "--version", $latestVersion, "--token", $env:WINGET_TOKEN, "--submit")
        foreach ($urlInfo in $downloadUrls) {
            $komacArgs += "--urls"
            $komacArgs += $urlInfo  # 传入带有 |x64 或 |x86 的完整字符串
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

# ==========================================
# 5. 写入状态文件
# ==========================================
$resultDir = "results"
if (-not (Test-Path $resultDir)) {
    New-Item -ItemType Directory -Path $resultDir | Out-Null
}

$resultFile = "$resultDir/$($PackageId).json"
$resultData = @{
    PackageId = $PackageId
    Version = $newVersion
    Status = $status
    PRLink = $prLink
    Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
}

# 状态比对：如果没有变化，就不写文件（避免高频轮询产生无意义的提交）
if (Test-Path $resultFile) {
    try {
        $oldData = Get-Content $resultFile -Raw | ConvertFrom-Json
        if ($oldData.Version -eq $resultData.Version -and $oldData.Status -eq $resultData.Status -and $oldData.PRLink -eq $resultData.PRLink) {
            Write-Host "State unchanged. Skipping status file update."
            exit 0
        }
    } catch {
        # 忽略解析旧的损坏 JSON
    }
}

$resultData | ConvertTo-Json | Out-File -FilePath $resultFile -Encoding utf8
