# PastureWalk - Windows development workflow helpers.
# Replaces the old Linux tmux/bashrc aliases (fstart, frun, lazygit, ranger, ...).
#
# Load it by adding this line to your PowerShell profile:
#   . "C:\Users\samwk\OneDrive\Documents\Projects\Pasture-Walk\scripts\dev-workflow.ps1"

$env:JAVA_HOME     = 'C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot'
$env:ANDROID_HOME  = "$env:LOCALAPPDATA\Android\Sdk"
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:PATH = (@(
    'C:\src\flutter\bin'
    "$env:JAVA_HOME\bin"
    'C:\Program Files\Git\cmd'
    "$env:ANDROID_HOME\platform-tools"
    "$env:ANDROID_HOME\cmdline-tools\latest\bin"
) + ($env:PATH -split ';') | Where-Object { $_ } | Select-Object -Unique) -join ';'

# Android Studio injects BOTH ANDROID_USER_HOME and ANDROID_PREFS_ROOT into its children.
# AGP resolves ANDROID_PREFS_ROOT as '<value>\.android', so a value of C:\Users\samwk\.android
# becomes C:\Users\samwk\.android\.android and conflicts with ANDROID_USER_HOME -> AGP hard-fails
# with 'Several environment variables ... contain different paths'. Drop the legacy variable.
Remove-Item Env:ANDROID_PREFS_ROOT -ErrorAction SilentlyContinue

$global:PastureWalkRoot = 'C:\Users\samwk\OneDrive\Documents\Projects\Pasture-Walk'

# ---------------------------------------------------------------- navigation
function proj { Set-Location $global:PastureWalkRoot }

# Replaces `fstart`: opens the project folder.
function fstart { proj; Write-Host 'PastureWalk: ready. Use fdev / frun to launch.' -ForegroundColor Green }

# ---------------------------------------------------------------- flutter
function frun      { proj; flutter run }
function fdev      { proj; flutter run --debug }
function fbuild    { proj; flutter build apk --release }
function fdapk     { proj; flutter build apk --debug }
function ftest     { proj; flutter test }
function fanalyze  { proj; flutter analyze }
function fdoctor   { flutter doctor -v }
function fdevices  { flutter devices }
function fpub      { proj; flutter pub get }
function fclean    { proj; flutter clean; flutter pub get }
function ffix      { proj; dart fix --apply }

# ---------------------------------------------------------------- git
function gs  { proj; git status }
function gd  { proj; git diff }
function gl  { proj; git log --oneline --graph --decorate -25 }
function ga  { proj; git add -A }
function gc  { param([Parameter(Mandatory)][string]$Message) proj; git commit -m $Message }
function gp  { proj; git push }
function gu  { proj; git pull --ff-only }

# Force-push rewritten history (branches + tags). Only use after a history rewrite.
function gp-force { proj; git push --force origin master; git push --force --tags origin }

# ---------------------------------------------------------------- search
function ffind {
    param([Parameter(Mandatory)][string]$Name)
    proj
    Get-ChildItem -Recurse -File -Filter $Name |
        Where-Object { $_.FullName -notmatch '\\(build|\.dart_tool|\.git)\\' }
}

function fgrep {
    param([Parameter(Mandatory)][string]$Pattern)
    proj
    Get-ChildItem -Recurse -File -Filter *.dart |
        Where-Object { $_.FullName -notmatch '\\(build|\.dart_tool|\.git)\\' } |
        Select-String -Pattern $Pattern
}

Write-Host 'PastureWalk helpers loaded (fstart, frun, fbuild, ftest, fanalyze, fdoctor, gs, gl, ...)' -ForegroundColor DarkGray
