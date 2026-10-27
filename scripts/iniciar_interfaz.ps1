[CmdletBinding()]
param(
    [string]$PhpPath = '',
    [string]$DbHost = '127.0.0.1',
    [int]$DbPort = 5432,
    [string]$DbName = 'autoaudit',
    [int]$Port = 8080,
    [int]$OnceSeconds = 0
)

$ErrorActionPreference = 'Stop'
if ($DbPort -lt 1 -or $DbPort -gt 65535) { throw 'DbPort debe estar entre 1 y 65535.' }
if ($Port -lt 1 -or $Port -gt 65535) { throw 'Port debe estar entre 1 y 65535.' }
if ($OnceSeconds -lt 0 -or $OnceSeconds -gt 60) { throw 'OnceSeconds debe estar entre 0 y 60.' }
$appRoot = Split-Path -Parent $PSScriptRoot
if (-not $PhpPath) {
    $cmd = Get-Command php.exe -ErrorAction SilentlyContinue
    if ($cmd) { $PhpPath = $cmd.Source }
    elseif (Test-Path 'C:\xampp1\php\php.exe') { $PhpPath = 'C:\xampp1\php\php.exe' }
    else { throw 'No se encontró php.exe. Use -PhpPath para indicar la ruta.' }
}
if (-not (Test-Path -LiteralPath $PhpPath)) { throw "No existe PHP: $PhpPath" }
if (-not (Test-Path -LiteralPath (Join-Path $appRoot 'app\index.php'))) { throw "No se encontró app\index.php en $appRoot" }

$old = @{}
foreach ($name in 'AUTOAUDIT_DB_HOST','AUTOAUDIT_DB_PORT','AUTOAUDIT_DB_NAME','AUTOAUDIT_TIMEZONE') {
    $old[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$sessionRoot = Join-Path ([IO.Path]::GetTempPath()) ('autoaudit-sessions-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $sessionRoot | Out-Null
$proc = $null
try {
    $env:AUTOAUDIT_DB_HOST = $DbHost
    $env:AUTOAUDIT_DB_PORT = [string]$DbPort
    $env:AUTOAUDIT_DB_NAME = $DbName
    $env:AUTOAUDIT_TIMEZONE = 'America/Guatemala'
    $phpDir = Split-Path -Parent $PhpPath
    $phpArgs = @('-n', '-d', "session.save_path=$sessionRoot")
    $extDir = Join-Path $phpDir 'ext'
    if (Test-Path (Join-Path $extDir 'php_pdo_pgsql.dll')) {
        $phpArgs += @('-d', "extension_dir=$extDir", '-d', 'extension=php_pdo_pgsql.dll')
        if (Test-Path (Join-Path $extDir 'php_pgsql.dll')) { $phpArgs += @('-d', 'extension=php_pgsql.dll') }
    }
    $phpArgs += @('-S', "127.0.0.1:$Port", '-t', (Join-Path $appRoot 'app'))
    $probe = & $PhpPath -n -d "extension_dir=$extDir" -d 'extension=php_pdo_pgsql.dll' -r 'exit(extension_loaded("pdo_pgsql") ? 0 : 1);' 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'PHP no pudo cargar pdo_pgsql.dll; verifique PhpPath y su carpeta ext.' }
    Write-Host "AutoAudit escuchando en http://127.0.0.1:$Port (DB $DbHost`:$DbPort/$DbName)"
    $si = [Diagnostics.ProcessStartInfo]::new(); $si.FileName = $PhpPath; $si.WorkingDirectory = $appRoot; $si.UseShellExecute = $false; $si.CreateNoWindow = $true
    if ($phpArgs | Where-Object { $_.Contains('"') }) { throw 'Argumento con comillas no admitido.' }
    $si.Arguments = ($phpArgs | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $proc = [Diagnostics.Process]::Start($si)
    if ($OnceSeconds -gt 0) { Start-Sleep -Seconds $OnceSeconds }
    else { Wait-Process -Id $proc.Id }
}
finally {
    if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    foreach ($name in $old.Keys) {
        [Environment]::SetEnvironmentVariable($name, $old[$name], 'Process')
        if ($null -eq $old[$name]) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
        else { Set-Item "Env:$name" $old[$name] }
    }
    $resolvedTemp = (Resolve-Path ([IO.Path]::GetTempPath())).Path.TrimEnd('\') + '\'
    $resolvedSession = [IO.Path]::GetFullPath($sessionRoot)
    if ($resolvedSession.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolvedSession) -match '^autoaudit-sessions-[0-9a-f]{32}$') {
        Remove-Item -LiteralPath $resolvedSession -Recurse -Force -ErrorAction SilentlyContinue
    }
}
