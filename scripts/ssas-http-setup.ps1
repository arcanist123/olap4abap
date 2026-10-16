# Publishes the local SSAS instance over HTTP (msmdpump.dll in IIS), so that scripts/xmla-proxy.py can stand in front
# of it as it stands in front of the reference and SAP (its backend "ssas", http://localhost:8086/).
# The pump is IIS's own site OLAP on http://127.0.0.1:8087/msmdpump.dll (this machine only; no Default Web Site).
#
# Run once in an elevated Windows PowerShell:
#     powershell -ExecutionPolicy Bypass -File scripts\ssas-http-setup.ps1
#     powershell -ExecutionPolicy Bypass -File scripts\ssas-http-setup.ps1 -Instance 'localhost\SSAS_TAB'
#
# It enables IIS's ISAPI extensions, copies the instance's isapi folder to C:\inetpub\olap, points msmdpump.ini at the
# instance, creates the application pool OLAP and the site OLAP (port 8087) with anonymous access under the pool's
# identity (the proxy opens a connection per request, which Windows authentication's handshake does not survive), and
# makes IIS APPPOOL\OLAP an administrator of the instance. Only for a development machine: anyone who reaches
# http://127.0.0.1:8087/msmdpump.dll is an administrator of the instance. Run it again after an SSAS update.
param(
    [string]$Instance = 'localhost\SSAS_TAB',
    [string]$Service = 'MSOLAP$SSAS_TAB',
    [string]$Target = 'C:\inetpub\olap',
    [string]$Site = 'OLAP',
    [int]$Port = 8087,
    [string]$Pool = 'OLAP'
)
$ErrorActionPreference = 'Stop'

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script in an elevated PowerShell (Run as administrator).'
}

# the isapi folder next to the instance's msmdsrv.exe
$binary = (Get-CimInstance Win32_Service -Filter "Name='$Service'").PathName
if (-not $binary) { throw "Service $Service not found." }
$bin = Split-Path ($binary -replace '^"([^"]+)".*$', '$1')
$isapi = Join-Path $bin 'isapi'
if (-not (Test-Path (Join-Path $isapi 'msmdpump.dll'))) { throw "No msmdpump.dll in $isapi." }

Write-Host 'Enabling IIS ISAPI extensions and filters'
Enable-WindowsOptionalFeature -Online -All -NoRestart -FeatureName IIS-ISAPIExtensions, IIS-ISAPIFilter | Out-Null

$appcmd = Join-Path $env:windir 'system32\inetsrv\appcmd.exe'
function AppCmd {
    & $appcmd @args
    if ($LASTEXITCODE -ne 0) { throw "appcmd $args failed ($LASTEXITCODE)" }
}

# a running worker process holds the pump's files open: stop the pool while they are copied (started again below)
if (& $appcmd list apppool /name:$Pool /state:Started) {
    Write-Host "Stopping application pool $Pool"
    AppCmd stop apppool /apppool.name:$Pool | Out-Null
    Start-Sleep -Seconds 2
}

Write-Host "Copying $isapi to $Target"
New-Item -ItemType Directory -Force $Target | Out-Null
Copy-Item (Join-Path $isapi '*') $Target -Recurse -Force
$ini = Join-Path $Target 'msmdpump.ini'
$text = Get-Content $ini -Raw
$text = $text -replace '<ServerName>[^<]*</ServerName>', "<ServerName>$Instance</ServerName>"
# the 2025 pump refuses http ("must use secure channels") unless told otherwise; the site listens on 127.0.0.1 only
$text = $text -replace '\s*<RequireSecureChannel>[^<]*</RequireSecureChannel>', ''
$text = $text -replace '</ConfigurationSettings>', "`t<RequireSecureChannel>0</RequireSecureChannel>`r`n</ConfigurationSettings>"
Set-Content $ini $text -Encoding ASCII
$dll = Join-Path $Target 'msmdpump.dll'

Write-Host "Application pool $Pool and site $Site on 127.0.0.1:$Port"
if (-not (& $appcmd list apppool /name:$Pool)) { AppCmd add apppool /name:$Pool '/managedRuntimeVersion:' }
AppCmd set apppool /apppool.name:$Pool /processModel.identityType:ApplicationPoolIdentity
if (-not (& $appcmd list site "/name:$Site")) {
    AppCmd add site "/name:$Site" "/bindings:http/127.0.0.1:${Port}:" "/physicalPath:$Target"
}
AppCmd set app "$Site/" "/applicationPool:$Pool"

Write-Host 'Handler, ISAPI restriction and anonymous access'
& $appcmd set config "$Site" /section:handlers "/-[name='OLAP']" /commit:apphost 2>$null | Out-Null
AppCmd set config "$Site" /section:handlers "/+[name='OLAP',path='*.dll',verb='*',modules='IsapiModule',scriptProcessor='$dll',resourceType='File',requireAccess='Execute',preCondition='bitness64']" /commit:apphost
AppCmd set config "$Site" /section:handlers '/accessPolicy:Read, Script, Execute' /commit:apphost
& $appcmd set config /section:isapiCgiRestriction "/-[path='$dll']" 2>$null | Out-Null
AppCmd set config /section:isapiCgiRestriction "/+[path='$dll',allowed='True',description='OLAP']"
AppCmd set config "$Site" /section:anonymousAuthentication /enabled:true '/userName:' /commit:apphost
& $appcmd set config "$Site" /section:windowsAuthentication /enabled:false /commit:apphost 2>$null | Out-Null

$identity = "IIS APPPOOL\$Pool"
Write-Host "Granting $identity read access to $Target"
icacls $Target /grant "${identity}:(OI)(CI)RX" | Out-Null

Write-Host "Making $identity an administrator of $Instance"
Import-Module SqlServer
$server = New-Object Microsoft.AnalysisServices.Server
$server.Connect($Instance)
try {
    $role = $server.Roles['Administrators']
    if (-not ($role.Members | Where-Object { $_.Name -eq $identity })) {
        $role.Members.Add((New-Object Microsoft.AnalysisServices.RoleMember($identity))) | Out-Null
        $role.Update()
    }
} finally {
    $server.Disconnect()
}

if (& $appcmd list apppool /name:$Pool /state:Started) { AppCmd recycle apppool /apppool.name:$Pool }
else { AppCmd start apppool /apppool.name:$Pool }
& $appcmd start site "/site.name:$Site" 2>$null | Out-Null
Write-Host "Checking http://127.0.0.1:${Port}/msmdpump.dll"
$body = '<Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/"><Body><Discover xmlns="urn:schemas-microsoft-com:xml-analysis"><RequestType>DBSCHEMA_CATALOGS</RequestType><Restrictions/><Properties/></Discover></Body></Envelope>'
$response = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:${Port}/msmdpump.dll" -Method Post -Body $body `
    -ContentType 'text/xml' -Headers @{ SOAPAction = 'urn:schemas-microsoft-com:xml-analysis:Discover' }
$catalogs = [regex]::Matches($response.Content, '<CATALOG_NAME>([^<]*)</CATALOG_NAME>') | ForEach-Object { $_.Groups[1].Value }
Write-Host "OK: catalogs $($catalogs -join ', ')"
