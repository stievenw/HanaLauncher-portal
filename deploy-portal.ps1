# HanaLauncher portal - publikasi rilis
# Salin build dari proyek launcher (HanaLauncherSetup.exe, HanaLauncher.msi,
# HanaLauncher-hashes.txt - HanaLauncher.exe TIDAK dipublikasikan ke web), tulis
# downloads/<v>/info.json, perbarui releases.json (indeks versi), commit, push.
param(
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [string]$Notes = "Rilis baru",
    [string]$Date = (Get-Date -Format 'yyyy-MM-dd'),
    [string]$LauncherProject = "E:\Project\Minecraft\Software\HanaLauncher",
    [string]$Repo = "stievenw/HanaLauncher-portal"
)

$ErrorActionPreference = "Stop"
$PortalRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Get-Sha256($Path) {
    (Get-FileHash $Path -Algorithm SHA256).Hash
}

function Get-SetupInfo($Dir, $Version) {
    $out = @{}
    foreach ($k in @("setup", "msi")) {
        $name = if ($k -eq "setup") { "HanaLauncherSetup.exe" }
                else { "HanaLauncher.msi" }
        $p = Join-Path $Dir $name
        if (Test-Path $p) {
            $out[$k] = [pscustomobject]@{
                file   = $name
                size   = (Get-Item $p).Length
                sha256 = Get-Sha256 $p
            }
        }
    }
    $out
}

function Write-InfoJson($Dir, $Version, $Notes, $Date, $IsPatch) {
    $info = [pscustomobject]@{
        version = $Version
        date    = $Date
        patch   = $IsPatch
        notes   = $Notes
        files   = [pscustomobject](Get-SetupInfo $Dir $Version)
        tag     = "v$Version"
    }
    $tmp = Join-Path $PortalRoot ".tmp\info.json"
    New-Item -ItemType Directory -Force -Path (Split-Path $tmp) | Out-Null
    $info | ConvertTo-Json -Depth 6 | Set-Content $tmp -Encoding UTF8
    Move-Item -Force $tmp (Join-Path $Dir "info.json")
}

$srcSetup = Join-Path $LauncherProject "setup\HanaLauncherSetup.exe"
$srcMsi   = Join-Path $LauncherProject "setup\HanaLauncher.msi"
$srcHash  = Join-Path $LauncherProject "setup\HanaLauncher-hashes.txt"

foreach ($f in @($srcSetup, $srcMsi, $srcHash)) {
    if (-not (Test-Path $f)) { throw "Tidak ditemukan: $f. Jalankan build-all.ps1 dulu." }
}

$manifestPath = Join-Path $PortalRoot "releases.json"
$manifest = if (Test-Path $manifestPath) { Get-Content $manifestPath -Raw | ConvertFrom-Json }
            else { [pscustomobject]@{ latest = ""; versions = @() } }

$prev = $manifest.latest
if ($prev -eq $Version) {
    Write-Warning "Versi $Version sudah menjadi latest - dilewati (jangan publish ulang)."
    exit 1
}

$dstDir = Join-Path $PortalRoot "downloads\$Version"
New-Item -ItemType Directory -Force -Path $dstDir | Out-Null

Copy-Item $srcSetup $dstDir -Force
Copy-Item $srcMsi   $dstDir -Force
Copy-Item $srcHash  $dstDir -Force

Write-Host "== Artifak $Version =="
foreach ($f in @("HanaLauncherSetup.exe", "HanaLauncher.msi")) {
    $p = Join-Path $dstDir $f
    Write-Host ("  {0,-22} {1,10}  {2}" -f $f, (Get-Item $p).Length, (Get-Sha256 $p))
}

$isPatch = $false
if ($prev) {
    $a = $prev -split '\.'; $b = $Version -split '\.'
    if ($a.Count -ge 2 -and $b.Count -ge 2 -and $a[0] -eq $b[0] -and $a[1] -eq $b[1]) { $isPatch = $true }
}
Write-InfoJson $dstDir $Version $Notes $Date $isPatch
Write-Host "info.json dibuat -> patch = $isPatch"

$tag = "v$Version"
$relArgs = @("release", "create", $tag)
foreach ($f in @("HanaLauncherSetup.exe", "HanaLauncher.msi", "HanaLauncher-hashes.txt")) {
    $relArgs += (Join-Path $dstDir $f)
}
$relArgs += @("--repo", $Repo, "--title", $tag, "--notes", $Notes)
& gh $relArgs
Write-Host "GitHub Release dibuat: $tag"

$versions = @($manifest.versions) + @($Version)
$manifest.versions = @($versions | Sort-Object -Descending)
$manifest.latest = $Version

$tmp = Join-Path $PortalRoot ".tmp\releases.json"
New-Item -ItemType Directory -Force -Path (Split-Path $tmp) | Out-Null
$manifest | ConvertTo-Json -Depth 6 | Set-Content $tmp -Encoding UTF8
Move-Item -Force $tmp $manifestPath
Write-Host "releases.json (indeks) diperbarui -> latest = $Version"

Push-Location $PortalRoot
try {
    git add -A
    git commit -m "Rilis $Version" | Out-Null
    git push origin main
    Write-Host "Pushed ke $Repo (main)."
}
finally {
    Pop-Location
}