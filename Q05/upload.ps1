# Uploads the parts from <name>_upload to GitHub branch upload-<name> in batches, resumable.
# Files are staged straight from the parts folder (git hash-object), nothing is copied. Windows PowerShell 5.1, ASCII only.
param([Parameter(Mandatory=$true)][string]$Parts,
      [Parameter(Mandatory=$true)][string]$Repo,
      [int]$Batch = 25,
      [string]$Url = 'https://github.com/tvoyucishka-a11y/rusifycar-voice.git',
      [string]$Base = 'claude/elegant-feynman-9cfvxd')
$ErrorActionPreference = 'Stop'

function RunGit { & git @args | Out-Host; if ($LASTEXITCODE -ne 0) { throw ("git " + ($args -join ' ') + " -> kod $LASTEXITCODE") } }
function TryGit { & git @args | Out-Host; return ($LASTEXITCODE -eq 0) }

$Parts = (Resolve-Path -LiteralPath $Parts).Path.TrimEnd('\', '/')
$name = (Split-Path -Leaf $Parts) -replace '_upload$', ''
$branch = 'upload-' + $name
$dest = 'upload/' + $name
$all = @(Get-ChildItem -LiteralPath $Parts -File | Sort-Object Name)
$shaFile = $all | Where-Object { $_.Name -like '*.sha256' } | Select-Object -First 1
if (-not $shaFile) { throw "v $Parts net fayla .sha256 - snachala narezhte papku (pack.ps1)" }
$files = @($shaFile) + @($all | Where-Object { $_.Name -notlike '*.sha256' })
Write-Host ("Faylov: {0}, vetka na GitHub: {1}" -f $files.Count, $branch)

if (-not (Test-Path -LiteralPath (Join-Path $Repo '.git'))) {
    Write-Host "Kloniruyu repozitoriy (tolko oglavlenie) v $Repo ..."
    RunGit clone -q --filter=blob:none --no-checkout -b $Base $Url $Repo
}
Push-Location -LiteralPath $Repo
try {
    RunGit config http.postBuffer 524288000
    RunGit sparse-checkout set upload
    & git ls-remote --exit-code --heads origin $branch | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Host "Vetka $branch uzhe est - prodolzhayu"; $from = $branch } else { $from = $Base }
    RunGit fetch -q origin $from
    RunGit update-ref "refs/heads/$branch" FETCH_HEAD
    RunGit symbolic-ref HEAD "refs/heads/$branch"
    RunGit reset -q

    # what is already on GitHub: name -> size (from the tree, without downloading)
    $remote = @{}
    foreach ($l in @(& git ls-tree -l HEAD -- "$dest/")) {
        if ($l -match '^\S+ blob (\S+)\s+(\d+)\t(.+)$') { $remote[($matches[3] -replace '^.*/', '')] = @($matches[1], [int64]$matches[2]) }
    }
    if ($remote.ContainsKey($shaFile.Name)) {
        $old = (& git cat-file -p $remote[$shaFile.Name][0]) -join "`n"
        if ($old.Trim() -ne (Get-Content -LiteralPath $shaFile.FullName -Raw).Trim()) {
            Write-Host 'Na GitHub kuski ot drugoy narezki - zamenyayu ikh'
            RunGit rm -r -q --cached --ignore-unmatch -- $dest
            RunGit commit -q -m "$name : zanovo"
            $remote = @{}
        }
    }
    $todo = @($files | Where-Object { -not ($remote.ContainsKey($_.Name) -and $remote[$_.Name][1] -eq $_.Length) })
    Write-Host ("Uzhe na GitHub: {0}, ostalos: {1}" -f ($files.Count - $todo.Count), $todo.Count)

    for ($i = 0; $i -lt $todo.Count; $i += $Batch) {
        $chunk = @($todo[$i..([Math]::Min($i + $Batch, $todo.Count) - 1)])
        foreach ($f in $chunk) {
            $sha = (& git hash-object -w --no-filters -- $f.FullName)
            if ($LASTEXITCODE -ne 0 -or -not $sha) { throw ("ne udalos dobavit " + $f.Name) }
            RunGit update-index --add --cacheinfo ("100644,{0},{1}/{2}" -f $sha.Trim(), $dest, $f.Name)
        }
        $msg = "{0}: {1}-{2} iz {3}" -f $name, ($i + 1), ($i + $chunk.Count), $todo.Count
        RunGit commit -q -m $msg
        $ok = $false
        for ($try = 1; $try -le 4 -and -not $ok; $try++) {
            Write-Host ("Otpravlyayu {0}-{1} iz {2} (popytka {3})..." -f ($i + 1), ($i + $chunk.Count), $todo.Count, $try)
            $ok = TryGit push origin "HEAD:refs/heads/$branch"
            if (-not $ok) { Start-Sleep -Seconds (5 * $try) }
        }
        if (-not $ok) { throw 'push ne proshel 4 raza - zapustite batnik eshche raz, on prodolzhit s etogo mesta' }
    }
    Write-Host ''
    Write-Host "OK: vse kuski v vetke $branch na GitHub"
} finally { Pop-Location }
