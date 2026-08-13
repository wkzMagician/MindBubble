param(
    [string]$DestinationRoot = "$env:LOCALAPPDATA\DartloomBackups\mind_bubble",
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$VerifyOnly,
    [string]$BackupPath
)

$ErrorActionPreference = 'Stop'

function Get-Sha256([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-RelativeFilePath([string]$BasePath, [string]$FilePath) {
    $base = [IO.Path]::GetFullPath($BasePath).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $file = [IO.Path]::GetFullPath($FilePath)
    if (-not $file.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside its expected root: $file"
    }
    $file.Substring($base.Length)
}

function Test-Manifest([string]$Root) {
    $manifestPath = Join-Path $Root 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "Backup manifest does not exist: $manifestPath"
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    foreach ($entry in $manifest.files) {
        $copyPath = Join-Path $Root $entry.backupRelativePath
        if (-not (Test-Path -LiteralPath $copyPath)) {
            throw "Backup file is missing: $($entry.backupRelativePath)"
        }
        $copy = Get-Item -LiteralPath $copyPath
        if ($copy.Length -ne $entry.size -or (Get-Sha256 $copyPath) -ne $entry.sha256) {
            throw "Backup file failed verification: $($entry.backupRelativePath)"
        }
    }
    $manifest
}

if ($VerifyOnly) {
    if (-not $BackupPath) { throw '-BackupPath is required with -VerifyOnly' }
    $verified = Test-Manifest $BackupPath
    [ordered]@{
        backup = (Resolve-Path -LiteralPath $BackupPath).Path
        manifest = (Join-Path (Resolve-Path -LiteralPath $BackupPath).Path 'manifest.json')
        files = @($verified.files).Count
        bytes = (@($verified.files) | ForEach-Object { [int64]$_.size } | Measure-Object -Sum).Sum
        manifestVerified = $true
    } | ConvertTo-Json -Compress
    exit 0
}

$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss-fff')
$root = Join-Path $DestinationRoot $stamp
if (Test-Path -LiteralPath $root) { throw "Backup target already exists: $root" }
New-Item -ItemType Directory -Path (Join-Path $root 'data') -Force | Out-Null

$sources = @(
    [ordered]@{ id = 'documents-mindbubble'; path = (Join-Path $env:USERPROFILE 'Documents\MindBubble') },
    [ordered]@{ id = 'app-support'; path = (Join-Path $env:APPDATA 'com.example\mind_bubble') },
    [ordered]@{ id = 'legacy-database'; path = (Join-Path $env:USERPROFILE 'Documents\mind_bubble.db') },
    [ordered]@{ id = 'schema-config'; path = (Join-Path $RepositoryRoot 'dartloom.yaml') }
)
$sourceRecords = @()
$fileRecords = @()

foreach ($source in $sources) {
    $present = Test-Path -LiteralPath $source.path
    $sourceRecords += [ordered]@{
        id = $source.id
        absoluteSourcePath = $source.path
        backupAbsolutePath = (Join-Path $root "data\$($source.id)")
        present = $present
    }
    if (-not $present) { continue }

    $sourceItem = Get-Item -LiteralPath $source.path -Force
    if (($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing reparse-point source: $($source.path)"
    }
    $destinationBase = Join-Path $root "data\$($source.id)"
    New-Item -ItemType Directory -Path $destinationBase -Force | Out-Null
    $files = if ($sourceItem.PSIsContainer) {
        @(Get-ChildItem -LiteralPath $sourceItem.FullName -File -Force -Recurse | Sort-Object FullName)
    } else {
        @($sourceItem)
    }

    foreach ($file in $files) {
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing reparse-point file: $($file.FullName)"
        }
        $relative = if ($sourceItem.PSIsContainer) {
            Get-RelativeFilePath $sourceItem.FullName $file.FullName
        } else {
            $file.Name
        }
        $destination = Join-Path $destinationBase $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $destination
        $sourceHash = Get-Sha256 $file.FullName
        if ($file.Length -ne (Get-Item -LiteralPath $destination).Length -or $sourceHash -ne (Get-Sha256 $destination)) {
            throw "Copy verification failed: $($file.FullName)"
        }
        $fileRecords += [ordered]@{
            sourceId = $source.id
            sourceAbsolutePath = $file.FullName
            relativePath = $relative
            backupRelativePath = Get-RelativeFilePath $root $destination
            size = $file.Length
            mtimeUtc = $file.LastWriteTimeUtc.ToString('o')
            sha256 = $sourceHash
        }
    }
}

$manifest = [ordered]@{
    schemaVersion = 1
    createdAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    application = 'MindBubble'
    applicationVersion = '0.4.0+5'
    backupAbsolutePath = $root
    sources = $sourceRecords
    files = $fileRecords
}
$manifestPath = Join-Path $root 'manifest.json'
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding utf8
$verified = Test-Manifest $root

$restoreRoot = Join-Path $env:TEMP "mindbubble-backup-restore-$stamp"
if (Test-Path -LiteralPath $restoreRoot) { throw "Restore-test target already exists: $restoreRoot" }
New-Item -ItemType Directory -Path $restoreRoot | Out-Null
foreach ($entry in $verified.files) {
    $sourceCopy = Join-Path $root $entry.backupRelativePath
    $restorePath = Join-Path $restoreRoot $entry.backupRelativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $restorePath) -Force | Out-Null
    Copy-Item -LiteralPath $sourceCopy -Destination $restorePath
    if ((Get-Sha256 $restorePath) -ne $entry.sha256) { throw "Restore test failed: $($entry.backupRelativePath)" }
}
$resolvedRestore = (Resolve-Path -LiteralPath $restoreRoot).Path
$resolvedTemp = (Resolve-Path -LiteralPath $env:TEMP).Path
if (-not $resolvedRestore.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe restore-test cleanup path: $resolvedRestore"
}
Remove-Item -LiteralPath $resolvedRestore -Recurse -Force

Get-ChildItem -LiteralPath $root -File -Recurse -Force | ForEach-Object { $_.IsReadOnly = $true }
(Get-Item -LiteralPath $root -Force).Attributes = (Get-Item -LiteralPath $root -Force).Attributes -bor [IO.FileAttributes]::ReadOnly

[ordered]@{
    backup = $root
    manifest = $manifestPath
    files = $fileRecords.Count
    bytes = ($fileRecords | ForEach-Object { [int64]$_.size } | Measure-Object -Sum).Sum
    manifestVerified = $true
    restoreVerified = $true
    missingSources = @($sourceRecords | Where-Object { -not $_.present } | ForEach-Object { $_.id })
} | ConvertTo-Json -Compress
