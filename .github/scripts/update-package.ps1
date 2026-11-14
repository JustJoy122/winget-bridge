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

if ($Type -eq "github") {
    $releaseUrl = "https://api.github.com/repos/$TargetRepo/releases/latest"
    $release = Invoke-RestMethod -Uri $releaseUrl -Headers $headers

    $latestVersion = $release.tag_name -replace '^v', ''
    Write-Host "Upstream latest version: $latestVersion"

    if (-not $ReleaseNotesUrl) { $ReleaseNotesUrl = $release.html_url }

    $assets = $release.assets | Where-Object { $_.name -match $AssetRegex }
    if (-not $assets) { Write-Error "Cannot find asset matching regex: $AssetRegex"; exit 1 }
    
    foreach ($asset in $assets) {
        $arch = "x64"
        if ($asset.name -match "arm64|aarch64|arm-64") { $arch = "arm64" }
        elseif ($asset.name -match "x86-64|x86_64|amd64|x64") { $arch = "x64" }
        elseif ($asset.name -match "x86|ia32|32bit|i386") { $arch = "x86" }
        $downloadUrls += "$($asset.browser_download_url)|$arch"
    }
} elseif ($Type -eq "fixed_url") {
    $urlArray = $Urls.Split(",")
    $downloadUrls = $urlArray
    $firstUrl = $urlArray[0].Split("|")[0]
    $tempFile = "temp_setup.exe"
    Write-Host "Downloading fixed URL to extract version: $firstUrl"
    
    # 💡 修复：改用 curl.exe 并加入最多 3 次的重试机制
    $maxRetries = 3
    $retryCount = 0
    $downloadSuccess = $false
    
    while ($retryCount -lt $maxRetries -and -not $downloadSuccess) {
        try {
            # -L 跟随重定向，-s 静默，-f 失败时不输出网页内容
            curl.exe -L -s -f -o $tempFile $firstUrl
            if (Test-Path $tempFile) {
                $downloadSuccess = $true
            } else {
                throw "Download failed silently"
            }
        } catch {
            $retryCount++
            Write-Host "Download failed or interrupted. Retrying ($retryCount/$maxRetries) in 5 seconds..."
            if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
            Start-Sleep -Seconds 5
        }
    }
    
    if (-not $downloadSuccess) {
        Write-Error "Failed to download $firstUrl after $maxRetries attempts."
        exit 1
    }
    
    $exeVersion = (Get-Item $tempFile).VersionInfo.ProductVersion
    $rawVersion = $exeVersion -replace ',', '.' -replace ' ', ''
    
    if ($VersionRegex) {
        if ($rawVersion -match $VersionRegex) {
            if ($Matches.Count -gt 1) { $latestVersion = $Matches[1] }
            else { $latestVersion = $Matches[0] }
        } else { Write-Error "VersionRegex mismatch"; exit 1 }
    } else {
        $latestVersion = $rawVersion
        $segments = $latestVersion.Split('.')
        if ($segments.Length -eq 4 -and $segments[3] -eq '0') {
            $latestVersion = $segments[0..2] -join '.'
        }
    }
    Remove-Item $tempFile -Force
} else {
    Write-Error "Unknown Type: $Type"
    exit 1
}

$parts = $PackageId.Split('.')
$firstLetter = $parts[0].Substring(0, 1).ToLower()
$manifestPath = "$firstLetter/$($parts[0])/$($parts[1])"
$wingetApiUrl = "https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/$manifestPath"

$existingVersions = @()
try {
    $manifests = Invoke-RestMethod -Uri $wingetApiUrl -Headers $headers
    $existingVersions = $manifests | Where-Object { $_.type -eq "dir" } | Select-Object -ExpandProperty name
} catch {}

$isUpToDate = $existingVersions -contains $latestVersion
$status = "Unknown"
$prLink = ""
$newVersion = $latestVersion

if ($isUpToDate) {
    Write-Host "Already up to date. Found version $latestVersion in winget-pkgs."
    $status = "✅ 已是最新"
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
        
        # Komac 下载也加上重试
        $komacRetries = 3
        for ($i=0; $i -lt $komacRetries; $i++) {
            try {
                curl.exe -L -s -f -o komac.exe $komacAsset.browser_download_url
                break
            } catch { Start-Sleep -Seconds 3 }
        }
        
        $komacArgs = @("update", $PackageId, "--version", $latestVersion, "--token", $env:WINGET_TOKEN, "--submit")
        if ($ReleaseNotesUrl) { $komacArgs += "--release-notes-url"; $komacArgs += $ReleaseNotesUrl }
        foreach ($urlInfo in $downloadUrls) { $komacArgs += "--urls"; $komacArgs += $urlInfo }
        
        $komacOutput = & ./komac.exe $komacArgs 2>&1 | Out-String
        Write-Host $komacOutput
        
        if ($komacOutput -match 'https://github\.com/microsoft/winget-pkgs/pull/(\d+)') {
            $prLink = $Matches[0]
            $prNumber = $Matches[1]
            $status = "🚀 已自动提交 PR"
            
            $getPrUrl = "https://api.github.com/repos/microsoft/winget-pkgs/pulls/$prNumber"
            $prData = Invoke-RestMethod -Uri $getPrUrl -Headers $headers
            $newBody = $prData.body + "`n`n---`n*This PR was automatically generated by [winget-bridge](https://github.com/$env:GITHUB_REPOSITORY).*"
            $patchBody = @{ body = $newBody } | ConvertTo-Json
            Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/winget-pkgs/pulls/$prNumber" -Method Patch -Headers $headers -Body $patchBody -ContentType "application/json"
        } else {
            $status = "⚠️ PR 提交可能失败"
        }
    }
}

$resultDir = "results"
if (-not (Test-Path $resultDir)) { New-Item -ItemType Directory -Path $resultDir | Out-Null }

$resultData = @{
    PackageId = $PackageId
    Version = $newVersion
    Status = $status
    PRLink = $prLink
    Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
}

Write-Host "WRITING JSON: Version = $newVersion, Status = $status"
$resultData | ConvertTo-Json | Out-File -FilePath "$resultDir/$($PackageId).json" -Encoding utf8
