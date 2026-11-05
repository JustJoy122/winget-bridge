param (
    [string]$PackageId,
    [string]$Type,
    [string]$TargetRepo,
    [string]$AssetRegex,
    [string]$Urls,
    [string]$ReleaseNotesUrl,
    [string]$VersionRegex
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

    if (-not $ReleaseNotesUrl) { $ReleaseNotesUrl = $release.html_url }

    $assets = $release.assets | Where-Object { $_.name -match $AssetRegex }
    if (-not $assets) { Write-Error "Cannot find asset matching regex: $AssetRegex"; exit 1 }
    
    foreach ($asset in $assets) {
        # 修复架构识别优先级，避免 x86-64 被误判为 32 位
        $arch = "x64"
        if ($asset.name -match "arm64|aarch64|arm-64") { 
            $arch = "arm64" 
        } elseif ($asset.name -match "x86-64|x86_64|amd64|x64") {
            $arch = "x64"
        } elseif ($asset.name -match "x86|ia32|32bit|i386") { 
            $arch = "x86" 
        }
        $downloadUrls += "$($asset.browser_download_url)|$arch"
    }
} elseif ($Type -eq "fixed_url") {
    # --- 固定 URL 获取逻辑 ---
    $urlArray = $Urls.Split(",")
    $downloadUrls = $urlArray
    
    $firstUrl = $urlArray[0].Split("|")[0]
    $tempFile = "temp_setup.exe"
    Write-Host "Downloading fixed URL to extract version: $firstUrl"
    Invoke-WebRequest -Uri $firstUrl -OutFile $tempFile
    
    $exeVersion = (Get-Item $tempFile).VersionInfo.ProductVersion
    if (-not $exeVersion) { Write-Error "Failed to extract version from fixed URL executable."; exit 1 }
    
    $rawVersion = $exeVersion -replace ',', '.' -replace ' ', ''
    
    if ($VersionRegex) {
        if ($rawVersion -match $VersionRegex) {
            if ($Matches.Count -gt 1) { $latestVersion = $Matches[1] }
            else { $latestVersion = $Matches[0] }
            Write-Host "Custom Regex applied. Extracted: $latestVersion"
        } else {
            Write-Error "VersionRegex '$VersionRegex' did not match raw version '$rawVersion'"
            exit 1
        }
    } else {
        $latestVersion = $rawVersion
        $segments = $latestVersion.Split('.')
        if ($segments.Length -eq 4 -and $segments[3] -eq '0') {
            $latestVersion = $segments[0..2] -join '.'
        }
    }
    
    Write-Host "Final parsed version: $latestVersion"
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
    Write-Host "Package manifest directory not found."
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
    # 💡 修复：直接使用 $latestVersion，不再去计算不可靠的 $latestInWinget
    $newVersion = $latestVersion
} else {
    Write-Host "Version $latestVersion not found in winget-pkgs. Checking for open PRs..."
    
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
        
        $komacApiUrl = "https://api.github.com/repos/russellbanks/Komac/releases/latest"
        $komacRelease = Invoke-RestMethod -Uri $komacApiUrl -Headers $headers
        $komacAsset = $komacRelease.assets | Where-Object { $_.name -match "x86_64-pc-windows-msvc\.exe$" } | Select-Object -First 1
        if (-not $komacAsset) { Write-Error "Cannot find Komac x86_64 executable."; exit 1 }
        
        Invoke-WebRequest -Uri $komacAsset.browser_download_url -OutFile komac.exe
        
        $komacArgs = @("update", $PackageId, "--version", $latestVersion, "--token", $env:WINGET_TOKEN, "--submit")
        
        if ($ReleaseNotesUrl) {
            $komacArgs += "--release-notes-url"
            $komacArgs += $ReleaseNotesUrl
        }

        foreach ($urlInfo in $downloadUrls) {
            $komacArgs += "--urls"
            $komacArgs += $urlInfo
        }
        
        $komacOutput = & ./komac.exe $komacArgs 2>&1 | Out-String
        Write-Host $komacOutput
        
        # 提取 PR 链接并追加仓库署名
        if ($komacOutput -match 'https://github\.com/microsoft/winget-pkgs/pull/(\d+)') {
            $prLink = $Matches[0]
            $prNumber = $Matches[1]
            $status = "🚀 已自动提交 PR"
            
            Write-Host "Appending bridge repository link to PR body..."
            
            $getPrUrl = "https://api.github.com/repos/microsoft/winget-pkgs/pulls/$prNumber"
            $prData = Invoke-RestMethod -Uri $getPrUrl -Headers $headers
            
            $footer = "`n`n---`n*This PR was automatically generated by [winget-bridge](https://github.com/$env:GITHUB_REPOSITORY).*"
            $newBody = $prData.body + $footer
            
            $patchUrl = "https://api.github.com/repos/microsoft/winget-pkgs/pulls/$prNumber"
            $patchBody = @{ body = $newBody } | ConvertTo-Json
            
            try {
                Invoke-RestMethod -Uri $patchUrl -Method Patch -Headers $headers -Body $patchBody -ContentType "application/json"
                Write-Host "Successfully appended bridge link to PR body."
            } catch {
                Write-Host "Failed to update PR body: $_"
            }
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

if (Test-Path $resultFile) {
    try {
        $oldData = Get-Content $resultFile -Raw | ConvertFrom-Json
        if ($oldData.Version -eq $resultData.Version -and $oldData.Status -eq $resultData.Status -and $oldData.PRLink -eq $resultData.PRLink) {
            Write-Host "State unchanged. Skipping status file update."
            exit 0
        }
    } catch { }
}

$resultData | ConvertTo-Json | Out-File -FilePath $resultFile -Encoding utf8
