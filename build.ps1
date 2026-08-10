#!/usr/bin/env pwsh
# Cross-compile KFScanner for all supported platforms.
# Usage:  .\build.ps1
#         .\build.ps1 -Version "1.0.0"

param(
    [string]$Version = "1.0.0"
)

# Use Continue so that go's informational stderr lines don't abort the script.
$ErrorActionPreference = "Continue"

$Commit    = (git rev-parse --short HEAD 2>$null) -replace "`n",""
$BuildDate = (Get-Date -Format "yyyy-MM-dd")
$BuiltBy   = "goreleaser-local"
$MainPkg   = "./cmd/kfscanner"
$OutDir    = "dist"
$LdFlags   = "-s -w " +
             "-X github.com/kfscanner/kfscanner/pkg/version.Version=$Version " +
             "-X github.com/kfscanner/kfscanner/pkg/version.Commit=$Commit " +
             "-X github.com/kfscanner/kfscanner/pkg/version.BuildDate=$BuildDate " +
             "-X github.com/kfscanner/kfscanner/pkg/version.BuiltBy=$BuiltBy"

$Targets = @(
    @{ os="darwin";  arch="amd64"; out="kfscanner-darwin-amd64";    ext="" },
    @{ os="darwin";  arch="arm64"; out="kfscanner-darwin-arm64";    ext="" },
    @{ os="linux";   arch="386";   out="kfscanner-linux-386";       ext="" },
    @{ os="linux";   arch="amd64"; out="kfscanner-linux-amd64";     ext="" },
    @{ os="linux";   arch="arm64"; out="kfscanner-linux-arm64";     ext="" },
    @{ os="windows"; arch="386";   out="kfscanner-windows-386";     ext=".exe" },
    @{ os="windows"; arch="amd64"; out="kfscanner-windows-amd64";   ext=".exe" }
)

if (!(Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

Write-Host ""
Write-Host "  KF Scanner $Version  ($Commit  $BuildDate)" -ForegroundColor Cyan
Write-Host "  Building $($Targets.Count) binaries into /$OutDir ..." -ForegroundColor Cyan
Write-Host ""

$ok  = 0
$err = 0

foreach ($t in $Targets) {
    $bin = "$OutDir/$($t.out)$($t.ext)"
    $env:GOOS        = $t.os
    $env:GOARCH      = $t.arch
    $env:CGO_ENABLED = "0"

    $label = "$($t.os)/$($t.arch)".PadRight(16)
    Write-Host -NoNewline "  building $label  ->  $bin  "

    # Embed the KF Scanner icon + version metadata for Windows targets.
    # Requires go-winres (go install github.com/tc-hib/go-winres@latest).
    if ($t.os -eq "windows") {
        $winres = (Get-Command go-winres -ErrorAction SilentlyContinue).Source
        if (!$winres -and (Test-Path "$env:USERPROFILE\go\bin\go-winres.exe")) {
            $winres = "$env:USERPROFILE\go\bin\go-winres.exe"
        }
        if ($winres) {
            Push-Location $MainPkg
            & $winres make --arch $t.arch 2>$null | Out-Null
            Pop-Location
        } else {
            Write-Host "`n    (go-winres not found — Windows icon skipped)" -ForegroundColor Yellow
        }
    }

    # Redirect stderr to a temp file so go's informational "downloading…"
    # lines don't produce PowerShell NativeCommandError records.
    $stderrFile = [System.IO.Path]::GetTempFileName()
    go build -trimpath -ldflags $LdFlags -o $bin $MainPkg 2>$stderrFile
    $buildCode = $LASTEXITCODE

    if ($buildCode -eq 0) {
        $size = [math]::Round((Get-Item $bin).Length / 1MB, 1)
        Write-Host "OK  ($($size) MB)" -ForegroundColor Green
        $ok++
    } else {
        Write-Host "FAILED" -ForegroundColor Red
        Get-Content $stderrFile | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
        $err++
    }
    Remove-Item $stderrFile -ErrorAction SilentlyContinue
}

# restore env
Remove-Item Env:\GOOS        -ErrorAction SilentlyContinue
Remove-Item Env:\GOARCH      -ErrorAction SilentlyContinue
Remove-Item Env:\CGO_ENABLED -ErrorAction SilentlyContinue

Write-Host ""
if ($err -eq 0) {
    Write-Host "  All $ok builds succeeded." -ForegroundColor Green
} else {
    Write-Host "  $ok succeeded, $err failed." -ForegroundColor Red
    exit 1
}
Write-Host ""
