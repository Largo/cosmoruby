<#
Run the CosmoRuby acceptance tests against packaged APEs on Windows.

Runs the same .rb test files as the unix script (cosmo_tests/ci_smoke.rb,
ci_exit7.rb, test_sockets.rb, test_sqlite3.rb) plus a hard assertion that no run produced a
[BUG]/Segmentation fault block -- Ruby 4.0.6 segfaulted during VM init on
100% of Windows runs while every Linux check was green (Linux-only YJIT Rust
called from ruby_opt_init(); see PORTING-NOTES.md).  That is the regression
this job exists to catch.

PowerShell specifics, learned the hard way:
  * native stderr interleaved into a PowerShell pipeline gets mangled, so
    every run goes through `cmd /c ... > file 2>&1` and the file is read back;
  * PowerShell reports a cosmo APE's exit status shifted left by 8
    (exit 7 -> 1792), so status checks accept both;
  * quoting `-e` through pwsh -> cmd is a minefield: always use script files.

Usage: .github\scripts\test-cosmoruby.ps1 [-BinDir dist]
#>
param([string]$BinDir = "dist")

$ErrorActionPreference = "Continue"
$repo   = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$bin    = (Resolve-Path $BinDir).Path
$tests  = Join-Path $repo "third_party\ruby-wip-4.0.6\cosmo_tests"
$ruby   = Join-Path $bin "ruby.com"
$irb    = Join-Path $bin "irb.com"
$mini   = Join-Path $bin "miniruby.com"
$work   = Join-Path $env:TEMP ("cosmoruby-ci-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work -Force | Out-Null

$script:pass = 0
$script:fail = 0
function Ok($m)  { $script:pass++; Write-Host "[PASS] $m" }
function Bad($m) { $script:fail++; Write-Host "[FAIL] $m" }
function Section($m) { Write-Host ""; Write-Host "----- $m -----" }

# Run a native command through cmd, capturing merged stdout+stderr to a file.
function Invoke-Ape([string]$commandLine) {
    $log = Join-Path $work ("out-" + [guid]::NewGuid().ToString("N") + ".txt")
    cmd /c "$commandLine > `"$log`" 2>&1" | Out-Null
    $code = $LASTEXITCODE
    $text = ""
    if (Test-Path $log) { $text = (Get-Content $log -Raw); Remove-Item $log -Force }
    if ($null -eq $text) { $text = "" }
    Write-Host $text
    return [pscustomobject]@{ Code = $code; Text = $text }
}

# exit N from an APE shows up as N or (N << 8) depending on the shell layer
function Status-Is([int]$code, [int]$want) { return ($code -eq $want) -or ($code -eq ($want * 256)) }

Section "environment"
Write-Host "repo   : $repo"
Write-Host "bindir : $bin"
Write-Host "work   : $work"
Get-ChildItem $bin | Format-Table Name, Length | Out-String | Write-Host

Section "APE header"
foreach ($f in @($ruby, $irb, $mini)) {
    if (-not (Test-Path $f)) { Bad "missing $f"; continue }
    $b = [System.IO.File]::ReadAllBytes($f)[0..5]
    $magic = -join ($b | ForEach-Object { [char]$_ })
    if ($magic -eq "MZqFpD") { Ok "APE magic: $(Split-Path $f -Leaf)" }
    else { Bad "APE magic: $(Split-Path $f -Leaf) (got '$magic')" }
}

Set-Location $work
$allText = ""

Section "banner (informational, NOT a boot test)"
$r = Invoke-Ape "`"$ruby`" --version"
$allText += $r.Text

Section "ci_smoke.rb -- boot regression test (VM init, stdlib, fs, threads, sockets, sqlite3)"
$r = Invoke-Ape "`"$ruby`" `"$tests\ci_smoke.rb`" ci-arg-1 ci-arg-2"
$allText += $r.Text
if ((Status-Is $r.Code 0) -and ($r.Text -match "SMOKE-OK")) { Ok "ci_smoke.rb (status $($r.Code))" }
else { Bad "ci_smoke.rb (status $($r.Code))" }

Section "exit-status propagation (ci_exit7.rb must exit 7)"
$r = Invoke-Ape "`"$ruby`" `"$tests\ci_exit7.rb`""
$allText += $r.Text
if (Status-Is $r.Code 7) { Ok "exit status: raw=$($r.Code) (7 or 7<<8=1792)" }
else { Bad "exit status: raw=$($r.Code), want 7 or 1792" }

Section "socket diagnostic (cosmo_tests\ci_diag_sockets.rb, informational, never fails)"
$r = Invoke-Ape "`"$ruby`" `"$tests\ci_diag_sockets.rb`""
$allText += $r.Text

Section "socket/TCP acceptance (cosmo_tests/test_sockets.rb)"
$r = Invoke-Ape "`"$ruby`" `"$tests\test_sockets.rb`""
$allText += $r.Text
if ((Status-Is $r.Code 0) -and ($r.Text -match "SOCKET-OK")) { Ok "test_sockets.rb" }
else { Bad "test_sockets.rb (status $($r.Code))" }

Section "sqlite3 acceptance (cosmo_tests/test_sqlite3.rb)"
$r = Invoke-Ape "`"$ruby`" `"$tests\test_sqlite3.rb`""
$allText += $r.Text
if ((Status-Is $r.Code 0) -and ($r.Text -match "failures=0")) { Ok "test_sqlite3.rb" }
else { Bad "test_sqlite3.rb (status $($r.Code))" }

Section "irb.com boots (pipe mode)"
$r = Invoke-Ape "echo puts 40 + 2 | `"$irb`""
$allText += $r.Text
if ($r.Text -match "42") { Ok "irb.com" } else { Bad "irb.com" }

Section "miniruby.com boots"
$miniScript = Join-Path $work "mini.rb"
Set-Content -Path $miniScript -Value 'puts "MINI-#{RUBY_VERSION}"' -Encoding ascii
$r = Invoke-Ape "`"$mini`" `"$miniScript`""
$allText += $r.Text
if ($r.Text -match "MINI-4\.") { Ok "miniruby.com" } else { Bad "miniruby.com" }

Section "no crash signatures in any output"
if ($allText -match "\[BUG\]" -or $allText -match "Segmentation fault") {
    Bad "crash signature found in output (this is the 4.0.6 VM-init regression)"
} else {
    Ok "no [BUG]/segfault blocks"
}

Set-Location $repo
Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "===== RESULT: pass=$script:pass fail=$script:fail ====="
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
