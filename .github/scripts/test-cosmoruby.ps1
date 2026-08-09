<#
Run the CosmoRuby acceptance tests against packaged APEs on Windows.

Runs the same .rb test files as the unix script (cosmo_tests/ci_smoke.rb,
ci_exit7.rb, test_sqlite3.rb) plus a hard assertion that no run produced a
[BUG]/Segmentation fault block -- Ruby 4.0.6 segfaulted during VM init on
100% of Windows runs while every Linux check was green (Linux-only YJIT Rust
called from ruby_opt_init(); see PORTING-NOTES.md).  That is the regression
this job exists to catch.

PowerShell specifics, learned the hard way:
  * native stderr interleaved into a PowerShell pipeline gets mangled, so
    every run goes through `cmd /c ... > file 2>&1` and the file is read back;
  * quoting `-e` through pwsh -> cmd is a minefield: always use script files.

Exit statuses used to arrive here shifted left by 8 (exit 7 -> 1792), because
cosmopolitan Libc encodes a POSIX wait status into the Windows process exit
code.  ruby.c now bypasses that on Windows, so the checks below demand the
exact status and would catch a regression back to the old encoding.  See
PORTING-NOTES.md.

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

# An APE's exit status must be the plain status, like any other Windows
# program.  ($want * 256) is the cosmopolitan wait-status encoding this used
# to report and must never come back.
function Status-Is([int]$code, [int]$want) { return ($code -eq $want) }

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
if (Status-Is $r.Code 7) { Ok "exit status: $($r.Code)" }
else { Bad "exit status: got $($r.Code), want exactly 7 (1792 means the <<8 encoding is back)" }

Section "exact exit statuses (0, 1, 3, 7, 255, >255, exit!, uncaught exception)"
$exitOk = $true
foreach ($want in @(0, 1, 3, 7, 255)) {
    $f = Join-Path $work "exit$want.rb"
    Set-Content -Path $f -Value "exit $want" -Encoding ascii
    $r = Invoke-Ape "`"$ruby`" `"$f`""
    if (-not (Status-Is $r.Code $want)) { $exitOk = $false; Bad "exit $want -> $($r.Code)" }
}
# Ruby and POSIX narrow the status to eight bits: 300 & 0xff == 44.
$f = Join-Path $work "exit300.rb"
Set-Content -Path $f -Value "exit 300" -Encoding ascii
$r = Invoke-Ape "`"$ruby`" `"$f`""
if (-not (Status-Is $r.Code 44)) { $exitOk = $false; Bad "exit 300 -> $($r.Code), want 44" }
# exit! skips the teardown but must still report honestly.
$f = Join-Path $work "exitbang.rb"
Set-Content -Path $f -Value "exit! 3" -Encoding ascii
$r = Invoke-Ape "`"$ruby`" `"$f`""
if (-not (Status-Is $r.Code 3)) { $exitOk = $false; Bad "exit! 3 -> $($r.Code)" }
# An uncaught exception is 1.
$f = Join-Path $work "boom.rb"
Set-Content -Path $f -Value 'raise "boom"' -Encoding ascii
$r = Invoke-Ape "`"$ruby`" `"$f`""
if (-not (Status-Is $r.Code 1)) { $exitOk = $false; Bad "uncaught exception -> $($r.Code), want 1" }
if ($exitOk) { Ok "exit statuses are exact (incl. exit!, >255, exceptions)" }

Section "socket diagnostic (cosmo_tests\ci_diag_sockets.rb, informational, never fails)"
$r = Invoke-Ape "`"$ruby`" `"$tests\ci_diag_sockets.rb`""
$allText += $r.Text

Section "socket/TCP acceptance (cosmo_tests\test_sockets.rb)"
$r = Invoke-Ape "`"$ruby`" `"$tests\test_sockets.rb`""
$allText += $r.Text
if ((Status-Is $r.Code 0) -and ($r.Text -match "SOCKET-OK")) { Ok "test_sockets.rb" }
else { Bad "test_sockets.rb (status $($r.Code))" }

Section "sqlite3 acceptance (cosmo_tests/test_sqlite3.rb)"
$r = Invoke-Ape "`"$ruby`" `"$tests\test_sqlite3.rb`""
$allText += $r.Text
if ((Status-Is $r.Code 0) -and ($r.Text -match "failures=0")) { Ok "test_sqlite3.rb" }
else { Bad "test_sqlite3.rb (status $($r.Code))" }

Section "openssl acceptance (cosmo_tests/test_openssl.rb)"
$r = Invoke-Ape "`"$ruby`" `"$tests\test_openssl.rb`""
$allText += $r.Text
if ((Status-Is $r.Code 0) -and ($r.Text -match "failures=0")) { Ok "test_openssl.rb" }
else { Bad "test_openssl.rb (status $($r.Code))" }

Section "nokogiri acceptance (cosmo_tests/test_nokogiri.rb)"
$r = Invoke-Ape "`"$ruby`" `"$tests\test_nokogiri.rb`""
$allText += $r.Text
if ((Status-Is $r.Code 0) -and ($r.Text -match "fail=0")) { Ok "test_nokogiri.rb" }
else { Bad "test_nokogiri.rb (status $($r.Code))" }

Section "bigdecimal acceptance (cosmo_tests/test_bigdecimal.rb)"
$r = Invoke-Ape "`"$ruby`" `"$tests\test_bigdecimal.rb`""
$allText += $r.Text
if ((Status-Is $r.Code 0) -and ($r.Text -match "fail=0")) { Ok "test_bigdecimal.rb" }
else { Bad "test_bigdecimal.rb (status $($r.Code))" }

Section "racc acceptance (cosmo_tests/test_racc.rb)"
$r = Invoke-Ape "`"$ruby`" `"$tests\test_racc.rb`""
$allText += $r.Text
if ((Status-Is $r.Code 0) -and ($r.Text -match "fail=0")) { Ok "test_racc.rb" }
else { Bad "test_racc.rb (status $($r.Code))" }

Section "nio4r acceptance (cosmo_tests/test_nio4r.rb)"
$r = Invoke-Ape "`"$ruby`" `"$tests\test_nio4r.rb`""
$allText += $r.Text
if ((Status-Is $r.Code 0) -and ($r.Text -match "fail=0")) { Ok "test_nio4r.rb" }
else { Bad "test_nio4r.rb (status $($r.Code))" }

Section "puma acceptance (cosmo_tests/test_puma.rb)"
$r = Invoke-Ape "`"$ruby`" `"$tests\test_puma.rb`""
$allText += $r.Text
if ((Status-Is $r.Code 0) -and ($r.Text -match "fail=0")) { Ok "test_puma.rb" }
else { Bad "test_puma.rb (status $($r.Code))" }

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

Section "self-executing APE (/zip/main.rb auto-run)"
# dist\zipmain.com is ruby.com with a two-file app appended by the build job's
# `zip` (Windows runners have none, and Compress-Archive cannot append to an
# APE).  ruby.c runs /zip/main.rb when the command line names no other
# program, so the packed binary *is* the app.
$zm = Join-Path $bin "zipmain.com"
if (-not (Test-Path $zm)) {
    Bad "zipmain.com missing from $bin"
} else {
    $r = Invoke-Ape "`"$zm`" zm-a zm-b"
    $allText += $r.Text
    if ($r.Text -match '"marker":"zipmain"') { Ok "zip main auto-run" } else { Bad "zip main auto-run" }
    if ($r.Text -match '"argv":\["zm-a","zm-b"\]') { Ok "zip main ARGV passthrough" } else { Bad "zip main ARGV passthrough" }
    if (($r.Text -match '"zero":"/zip/main\.rb"') -and ($r.Text -match '"dir":"/zip"')) { Ok 'zip main $0 and __dir__' } else { Bad 'zip main $0 and __dir__' }
    if ($r.Text -match '"lib":"require_relative-ok"') { Ok "zip main multi-file app (require_relative)" } else { Bad "zip main multi-file app (require_relative)" }
    if (Status-Is $r.Code 7) { Ok "zip main exit status: $($r.Code)" } else { Bad "zip main exit status: got $($r.Code), want exactly 7" }

    # A packed binary is an application, so Ruby claims NONE of the command
    # line: option-shaped arguments reach the app instead of Ruby's option
    # parser.  `myapp.com --version` has to behave like a native binary's.
    $r = Invoke-Ape "`"$zm`" --verbose -e --version -- x"
    $allText += $r.Text
    if ($r.Text -match '"argv":\["--verbose","-e","--version","--","x"\]') {
        Ok "zip main takes the whole command line (leading flags reach the app)"
    } else { Bad "zip main leading flags" }
    if ($r.Text -match "invalid option") { Bad "zip main: Ruby parsed an application argument" }
    else { Ok "zip main: no interpreter option parsing" }

    # Exit status is the app's, exactly.
    $zmExitOk = $true
    foreach ($want in @(0, 1, 3, 7, 255)) {
        $r = Invoke-Ape "`"$zm`" --exit=$want"
        if (-not (Status-Is $r.Code $want)) { $zmExitOk = $false; Bad "zip main --exit=$want -> $($r.Code)" }
    }
    if ($zmExitOk) { Ok "zip main exit statuses 0/1/3/7/255 are exact" }

    # Interpreter options stay reachable through RUBYOPT, which is how a
    # packed binary gets -I / -r / -w / --yjit without stealing them from the
    # app's own command line.
    $r = Invoke-Ape "set RUBYOPT=-w && `"$zm`""
    $allText += $r.Text
    if ($r.Text -match '"verbose":true') { Ok "RUBYOPT still reaches the interpreter" }
    else { Bad "RUBYOPT does not reach the interpreter" }

    # The escape hatch turns a packed binary back into a plain interpreter.
    $hatchScript = Join-Path $work "hatch.rb"
    Set-Content -Path $hatchScript -Value 'puts "hatch-ok"' -Encoding ascii
    $r = Invoke-Ape "set COSMORUBY_NO_ZIP_MAIN=1 && `"$zm`" `"$hatchScript`""
    $allText += $r.Text
    if (($r.Text -match "hatch-ok") -and ($r.Text -notmatch '"marker":"zipmain"')) {
        Ok "COSMORUBY_NO_ZIP_MAIN=1 suppresses auto-run"
    } else { Bad "COSMORUBY_NO_ZIP_MAIN=1 suppresses auto-run" }

    # ...and an unpacked ruby.com must be completely unaffected.
    $r = Invoke-Ape "echo puts 123 | `"$ruby`""
    $allText += $r.Text
    if ($r.Text -match "123") { Ok "plain ruby.com still reads stdin (no auto-run)" }
    else { Bad "plain ruby.com stdin" }
}

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
