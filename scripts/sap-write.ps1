<#
.SYNOPSIS
Writes ABAP classes and interfaces from src/ into SAP with sapcli and activates them (the PowerShell version of
scripts/sap-write.sh).

.DESCRIPTION
For each object: the main source and the test classes of a class (classes have no local includes, CLAUDE.md), or
the source of an interface; then all objects are activated. Every sapcli call runs on its own, one after the other. A failed call stops that object and names the step; nothing is retried. The
objects must exist in SAP. Logon data comes from .env.sap (SAP_ASHOST, SAP_CLIENT, SAP_USER, SAP_PASSWORD, optional
SAP_PORT and SAP_USE_SSL), as for scripts/sap-sync.sh.

.EXAMPLE
.\scripts\sap-write.ps1 zzxxmla1_cl_mdx_engine
.\scripts\sap-write.ps1 zzxxmla1_cl_mdx_facts zzxxmla1_cl_mdx_engine
#>
param(
    [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
    [string[]] $Objects
)

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# logon data from .env.sap (KEY=VALUE lines)
$envFile = if ($env:SAP_ENV_FILE) { $env:SAP_ENV_FILE } else { Join-Path $root '.env.sap' }
if (Test-Path $envFile) {
    Get-Content $envFile | Where-Object { $_ -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$' } | ForEach-Object {
        Set-Item -Path "env:$($Matches[1])" -Value $Matches[2].Trim().Trim('"').Trim("'")
    }
}
foreach ($required in 'SAP_ASHOST', 'SAP_CLIENT', 'SAP_USER', 'SAP_PASSWORD') {
    if (-not (Get-Item -Path "env:$required" -ErrorAction SilentlyContinue)) {
        Write-Error "set $required in .env.sap"
        exit 2
    }
}
$logon = @('--ashost', $env:SAP_ASHOST, '--client', $env:SAP_CLIENT, '--user', $env:SAP_USER)
if ($env:SAP_PORT) { $logon += @('--port', $env:SAP_PORT) }
if ($env:SAP_USE_SSL -ne 'true') { $logon += '--no-ssl' }

# runs one sapcli call; returns its output and whether it succeeded
function Invoke-Sapcli([string[]] $arguments) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    # stderr lines arrive as ErrorRecords in Windows PowerShell; their text is the line
    $output = (& sapcli @logon @arguments 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { "$_" }
        } | Where-Object { $_ -ne 'System.Management.Automation.RemoteException' }) -join "`n"
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previous
    return [pscustomobject]@{ Ok = ($code -eq 0); Output = $output }
}

# the short reason of a failed call: the HTTP error and ICM code, not the whole error page
function Get-Reason([string] $output) {
    $lines = $output -split "`n" | Where-Object { $_ -match '^\s*(Exception|Error|\d{3}\s*$)' } |
        ForEach-Object { $_.Trim() } | Select-Object -First 3
    if (-not $lines) {
        $lines = $output -split "`n" | Where-Object { $_ -match '\S' -and $_ -notmatch '[<{}]' } | Select-Object -First 2
    }
    $icm = [regex]::Match($output, 'ICM[A-Z]+').Value
    return ((@($lines) + @($icm)) | Where-Object { $_ }) -join ' '
}

$status = 0
$written = @()
foreach ($object in $Objects) {
    $base = $object.ToLower()
    $name = $object.ToUpper()
    $steps = @()
    if (Test-Path "src/$base.intf.abap") {
        $steps += , @('interface source', @('interface', 'write', $name, "src/$base.intf.abap"))
    } else {
        $steps += , @('main source', @('class', 'write', '--type', 'main', $name, "src/$base.clas.abap"))
        if (Test-Path "src/$base.clas.testclasses.abap") {
            $steps += , @('test classes', @('class', 'write', '--type', 'testclasses', $name, "src/$base.clas.testclasses.abap"))
        }
    }
    $failed = $false
    foreach ($step in $steps) {
        $result = Invoke-Sapcli $step[1]
        if ($result.Ok) {
            Write-Host "   $name $($step[0]) written"
        } else {
            Write-Host "== ${name}: writing the $($step[0]) failed: $(Get-Reason $result.Output)" -ForegroundColor Red
            $failed = $true
            $status = 1
            break
        }
    }
    if (-not $failed) { $written += $object }
}

foreach ($object in $written) {
    $name = $object.ToUpper()
    $kind = if (Test-Path "src/$($object.ToLower()).intf.abap") { 'interface' } else { 'class' }
    $result = Invoke-Sapcli @($kind, 'activate', $name)
    $summary = ($result.Output -split "`n" | Where-Object { $_ -match '^Errors' }) -join ' '
    if (-not $summary) { $summary = Get-Reason $result.Output }
    Write-Host "== ${name}: $summary"
    $messages = $result.Output -split "`n" | Where-Object { $_ -match '^\s+(E|W):' -or $_ -match '^-- ' }
    if ($result.Output -match '(?m)^\s+E:' -or -not $result.Ok) {
        $messages | Where-Object { $_ -notmatch 'POSIX is deprecated' } | ForEach-Object { Write-Host $_ }
        $status = 1
    }
}
exit $status
