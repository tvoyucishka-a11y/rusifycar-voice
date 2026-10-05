# Folder/file -> <name>.zip -> <name>_upload\<name>.zip.partNNN (20 MB each) + sha256. Windows PowerShell 5.1, ASCII only.
param([Parameter(Mandatory=$true)][string]$Path)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$src = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\', '/')
$name = Split-Path -Leaf $src
$parent = Split-Path -Parent $src
$up = Join-Path $parent ($name + '_upload')
$zip = Join-Path $parent ($name + '.zip')
if (Test-Path -LiteralPath $up) { Remove-Item -LiteralPath $up -Recurse -Force }
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
New-Item -ItemType Directory -Path $up | Out-Null

Write-Host "Zip: $zip"
if (Test-Path -LiteralPath $src -PathType Container) {
    [System.IO.Compression.ZipFile]::CreateFromDirectory($src, $zip, [System.IO.Compression.CompressionLevel]::Optimal, $true)
} else {
    $za = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
    try { [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($za, $src, $name, [System.IO.Compression.CompressionLevel]::Optimal) }
    finally { $za.Dispose() }
}

$partSize = 20MB
$buf = New-Object byte[] $partSize
$fs = [System.IO.File]::OpenRead($zip)
$i = 0
try {
    while ($true) {
        $got = 0
        while ($got -lt $partSize) {
            $n = $fs.Read($buf, $got, $partSize - $got)
            if ($n -le 0) { break }
            $got += $n
        }
        if ($got -eq 0) { break }
        $part = Join-Path $up ('{0}.zip.part{1:D3}' -f $name, $i)
        $out = [System.IO.File]::Create($part)
        try { $out.Write($buf, 0, $got) } finally { $out.Close() }
        $i++
        if ($got -lt $partSize) { break }
    }
} finally { $fs.Close() }

$h = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLower()
$sz = (Get-Item -LiteralPath $zip).Length
Set-Content -LiteralPath (Join-Path $up ($name + '.zip.sha256')) -Value ("$h  $name.zip  $sz") -Encoding Ascii
Remove-Item -LiteralPath $zip -Force
Write-Host ("OK: $up  ($i kuskov, $sz bayt)")
