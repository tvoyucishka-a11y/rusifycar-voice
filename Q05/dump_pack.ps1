# Picks the stock voice app (WT_TSpeech / com.tinnove.wecarspeech), build.prop, onnxruntime and car framework jars
# out of a Q05 system dump, plus a full file listing, then packs them with pack.ps1. Windows PowerShell 5.1, ASCII only.
param([Parameter(Mandatory=$true)][string]$Dump)
$ErrorActionPreference = 'Stop'

$sep = [System.IO.Path]::DirectorySeparatorChar
$root = (Resolve-Path -LiteralPath $Dump).Path.TrimEnd('\', '/')
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out = Join-Path $here 'q05_dump'
if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
New-Item -ItemType Directory -Path $out | Out-Null

function Rel($full) { return $full.Substring($root.Length).TrimStart('\', '/') }

function CopyRel($full) {
    $dst = Join-Path $out (Rel $full)
    $dir = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Copy-Item -LiteralPath $full -Destination $dst -Recurse -Force
}

Write-Host "Damp: $root"
Write-Host 'Spisok vsekh faylov...'
$all = @(Get-ChildItem -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue)
$all | ForEach-Object {
    $size = if ($_.PSIsContainer) { '<DIR>' } else { $_.Length }
    "{0}`t{1}" -f (Rel $_.FullName), $size
} | Set-Content -LiteralPath (Join-Path $out 'listing.txt') -Encoding UTF8
Write-Host ("  {0} elementov" -f $all.Count)

# 1) papki/fayly golosovogo
$appRe = '(?i)tspeech|wecarspeech|wecar_speech'
$picked = @()
foreach ($it in $all) {
    if ($it.Name -notmatch $appRe) { continue }
    $inside = $false
    foreach ($p in $picked) { if ($it.FullName.StartsWith($p + $sep)) { $inside = $true; break } }
    if ($inside) { continue }
    Write-Host ("  golosovoy: " + (Rel $it.FullName))
    CopyRel $it.FullName
    $picked += $it.FullName
}
if ($picked.Count -eq 0) { Write-Host '  VNIMANIE: papka golosovogo (WT_TSpeech) ne naydena - otpravlyu tolko spisok faylov' }

# 2) build.prop, onnxruntime, kar-frameworki
$fileRe = '(?i)^(build\.prop|default\.prop|prop\.default)$|onnxruntime'
$fwRe = '(?i)tinnove|wecar|incall|changan|iflytek|speech|voice|\bcar'
foreach ($it in $all) {
    if ($it.PSIsContainer) { continue }
    $inside = $false
    foreach ($p in $picked) { if ($it.FullName.StartsWith($p + $sep)) { $inside = $true; break } }
    if ($inside) { continue }
    $isFw = ($it.FullName -match '(?i)[\\/]framework[\\/]') -and ($it.Extension -match '(?i)^\.(jar|apk)$') -and ($it.Name -match $fwRe)
    if (($it.Name -match $fileRe) -or $isFw) {
        Write-Host ("  " + (Rel $it.FullName))
        CopyRel $it.FullName
    }
}

& (Join-Path $here 'pack.ps1') -Path $out
