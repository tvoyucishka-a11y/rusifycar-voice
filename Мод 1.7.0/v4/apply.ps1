# Q7PATCH1 applier: OLD.apk + patch -> NEW.apk, then SHA-256 check. Windows PowerShell 5.1 compatible, ASCII only.
param([Parameter(Mandatory=$true)][string]$Old,
      [Parameter(Mandatory=$true)][string]$Patch,
      [Parameter(Mandatory=$true)][string]$Out)
$ErrorActionPreference = 'Stop'

function Hex([byte[]]$b) { return ([System.BitConverter]::ToString($b)).Replace('-', '').ToLower() }

function CopyN($src, $dst, [int64]$count, [byte[]]$buf) {
    while ($count -gt 0) {
        $want = [int][Math]::Min([int64]$buf.Length, $count)
        $got = $src.Read($buf, 0, $want)
        if ($got -le 0) { throw 'unexpected end of file' }
        $dst.Write($buf, 0, $got)
        $count -= $got
    }
}

$pf = [System.IO.File]::OpenRead((Resolve-Path $Patch).Path)
$br = New-Object System.IO.BinaryReader($pf)
try {
    $magic = [System.Text.Encoding]::ASCII.GetString($br.ReadBytes(8))
    if ($magic -ne 'Q7PATCH1') { throw 'eto ne patch Q7PATCH1' }
    $oldSize = $br.ReadUInt64(); $oldSha = Hex $br.ReadBytes(32)
    $newSize = $br.ReadUInt64(); $newSha = Hex $br.ReadBytes(32)
    $n = $br.ReadUInt32()

    $oldPath = (Resolve-Path $Old).Path
    $len = (Get-Item -LiteralPath $oldPath).Length
    if ([uint64]$len -ne $oldSize) { throw ("staryy APK ne tot: razmer $len, nuzhen $oldSize") }
    Write-Host 'Proveryayu staryy APK (SHA-256)...'
    $h = (Get-FileHash -LiteralPath $oldPath -Algorithm SHA256).Hash.ToLower()
    if ($h -ne $oldSha) { throw ("staryy APK ne tot: SHA-256 $h, nuzhen $oldSha") }

    $of = [System.IO.File]::OpenRead($oldPath)
    $wf = [System.IO.File]::Create($Out)
    $buf = New-Object byte[] (4MB)
    try {
        for ($i = 0; $i -lt $n; $i++) {
            $t = $br.ReadByte()
            if ($t -eq 67) {          # 'C' copy from old
                $off = [int64]$br.ReadUInt64(); $ln = [int64]$br.ReadUInt64()
                [void]$of.Seek($off, [System.IO.SeekOrigin]::Begin)
                CopyN $of $wf $ln $buf
            } elseif ($t -eq 76) {    # 'L' literal bytes from the patch
                $ln = [int64]$br.ReadUInt64()
                while ($ln -gt 0) {
                    $want = [int][Math]::Min([int64]$buf.Length, $ln)
                    $got = $br.Read($buf, 0, $want)
                    if ($got -le 0) { throw 'patch obrezan' }
                    $wf.Write($buf, 0, $got); $ln -= $got
                }
            } else { throw ("bityy patch (op $t)") }
        }
    } finally { $wf.Close(); $of.Close() }
} finally { $br.Close() }

$sz = (Get-Item -LiteralPath $Out).Length
if ([uint64]$sz -ne $newSize) { throw ("rezultat ne sovpal po razmeru: $sz vmesto $newSize") }
Write-Host 'Proveryayu novyy APK (SHA-256)...'
$h2 = (Get-FileHash -LiteralPath $Out -Algorithm SHA256).Hash.ToLower()
if ($h2 -ne $newSha) { Remove-Item -LiteralPath $Out; throw ("rezultat ne sovpal po SHA-256") }
Write-Host ("OK: $Out ($sz bayt), SHA-256 sovpal")
