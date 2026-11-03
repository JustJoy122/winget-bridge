param (
    [string]$PackageId,
    [string]$Type,
    [string]$TargetRepo,
    [string]$AssetRegex,
    [string]$Urls,
    [string]$ReleaseNotesUrl # 💡 新增：接收更新日志链接
)

$ErrorActionPreference = "Stop"
Write-Host "Checking updates for: $PackageId (Type: $Type)"

$headers = @{
    "Authorization" = "Bearer $env:WINGET_TOKEN"
    "User-Agent" = "Winget-Bridge-Action"
}

$latestVersion = ""
$downloadUrls = @()

# 1 & 2. 获取版本与链接
if ($Type -eq "github") {
    $releaseUrl = "https://api.github.com/repos/$TargetRepo/releases/latest"
    $release = Invoke-RestMethod -Uri $releaseUrl -Headers $headers
    $latestVersion = $release.tag_name -replace '^v', ''
    
    if (-not $ReleaseNotesUrl) { $ReleaseNotesUrl = $release.html_url } # 自动获取 GitHub Release 链接

    $assets = $release.assets | Where-Object { $_.name -match $AssetRegex }
    if (-not $assets) { Write-Error "Cannot find asset matching regex: $AssetRegex"; exit 1 }
    
    foreach ($asset in $assets) {
        $arch = "x64"
        if ($asset.name -match "arm64|aarch64") { $arch = "arm64" }
        elseif ($asset.name -match "x86|ia32|32bit") { $arch = "x86" }
        $downloadUrls += "$($asset.browser_download_url)|$arch"
    }
} elseif ($Type -eq "fixed_url") {
    $urlArray = $Urls.Split(",")
    $downloadUrls = $urlArray
    
    $firstUrl = $urlArray[0].Split("|")[0]
    $tempFile = "temp_setup.exe"
    Write-Host "Downloading fixed URL to extract version: $firstUrl"
    Invoke-WebRequest -Uri $firstUrl -OutFile $tempFile
    
    $exeVersion = (Get-Item $tempFile).VersionInfo.ProductVersion
    if (-not $exeVersion) { Write-Error "Failed to extract version"; exit 1 }
    
    # 💡 修复 1：清理版本号，并强制去掉末尾的 .0
    $latestVersion = $exeVersion -replace ',', '.' -replace ' ', '' -replace '\.0$', ''
    Write-Host "Upstream latest version: $latestVersion"
    Remove-Item $tempFile -Force
}

# 3. 获取 winget 当前版本
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
} catch { }

$latestInWinget = "0.0.0"
if ($existingVersions.Count -gt 0) {
    $latestInWinget = $existingVersions | Sort-Object { 
        try { [version]($_ -replace '[^0-9\.]', '') } catch { [version]'0.0.0' }
    } -Descending | Select-Object -First 1
}

$isUpToDate = $existingVersions -contains $latestVersion

# 4. 查重与提交
$status = "Unknown"
$prLink = ""
$newVersion = $latestVersion

if ($isUpToDate) {
    Write-Host "Already up to date. Found version $latestVersion in winget-pkgs."
    $status = "✅ 已是最新"
    $newVersion = $latestInWinget 
} else {
    $searchQuery = "repo:microsoft/winget-pkgs is:pr is:open $PackageId"
    $searchUrl = "https://api.github.com/search/issues?q=$([uri]::EscapeDataString($searchQuery))"
    $searchResult = Invoke-RestMethod -Uri $searchUrl -Headers $headers

    $validPr = $searchResult.items | Where-Object { $_.title -match [regex]::Escape($PackageId) } | Select-Object -First 1

    if ($validPr) {
        $status = "⏳ PR 等待审核"
        $prLink = $validPr.html_url
    } else {
        Write-Host "No open PRs found. Submitting new PR..."
        
        $komacApiUrl = "https://api.github.com/repos/russellbanks/Komac/releases/latest"
        $komacRelease = Invoke-RestMethod -Uri $komacApiUrl -Headers $headers
        $komacAsset = $komacRelease.assets | Where-Object { $_.name -match "x86_64-pc-windows-msvc\.exe$" } | Select-Object -First 1
        Invoke-WebRequest -Uri $komacAsset.browser_download_url -OutFile komac.exe
        
        $komacArgs = @("update", $PackageId, "--version", $latestVersion, "--token", $env:WINGET_TOKEN, "--submit")
        
        # 💡 修复 2：传入 ReleaseNotesUrl
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
        
        # 💡 修复 3：直接从输出提取 PR 链接
        if ($komacOutput -match 'https://github\.com/microsoft/winget-pkgs/pull/\d+') {
            $prLink = $Matches[0]
            $status = "🚀 已自动提交 PR"
        } else {
            $status = "⚠️ PR 提交可能失败"
        }
    }
}

# 5. 写入状态
$resultDir = "results"
if (-not (Test-Path $resultDir)) { New-Item -ItemType Directory -Path $resultDir | Out-Null }
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
            exit 0
        }
    } catch { }
}
$resultData | ConvertTo-Json | Out-File -FilePath $resultFile -Encoding utf8
