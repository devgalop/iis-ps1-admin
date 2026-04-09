#Requires -RunAsAdministrator
#Requires -Modules WebAdministration

<#
.SYNOPSIS
    Crea sitios web y Application Pools en IIS a partir de un archivo CSV.

.DESCRIPTION
    Lee el archivo sites.csv del mismo directorio con las columnas:
      Name         - Nombre del sitio y del Application Pool
      Port         - Puerto del binding HTTP
      PhysicalPath - Ruta física del sitio en disco

    Para cada entrada:
      1. Crea el Application Pool si no existe.
      2. Crea el directorio físico si no existe.
      3. Crea el sitio web con binding *:{Port}: si no existe.
      El procesamiento continúa con las demás entradas si una falla.

.NOTES
    El CSV debe estar en el mismo directorio que el script y llamarse sites.csv.
#>

Set-StrictMode -Version Latest

# ─────────────────────────────────────────────
# Logging
# ─────────────────────────────────────────────
$Script:LogFile = $null

function Initialize-Log {
    $logsDir = Join-Path $PSScriptRoot 'logs'
    if (-not (Test-Path $logsDir)) {
        New-Item -ItemType Directory -Path $logsDir | Out-Null
    }
    $timestamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $Script:LogFile = Join-Path $logsDir "create_sites_and_pools_$timestamp.log"
    Write-Log "INFO" "Log iniciado: $Script:LogFile"
}

function Write-Log {
    param(
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level,
        [string]$Message
    )
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $Script:LogFile -Value $entry
    switch ($Level) {
        'ERROR' { Write-Host $entry -ForegroundColor Red    }
        'WARN'  { Write-Host $entry -ForegroundColor Yellow }
        default { Write-Host $entry }
    }
}

# ─────────────────────────────────────────────
# Crear Application Pool
# ─────────────────────────────────────────────
function New-IISAppPool {
    param([string]$PoolName)

    if (Test-Path "IIS:\AppPools\$PoolName") {
        Write-Log "WARN" "[$PoolName] El Application Pool ya existe. Se omite la creación."
        return
    }

    New-WebAppPool -Name $PoolName | Out-Null
    Write-Log "INFO" "[$PoolName] Application Pool creado exitosamente."
}

# ─────────────────────────────────────────────
# Crear sitio web
# ─────────────────────────────────────────────
function New-IISSite {
    param(
        [string]$SiteName,
        [int]   $Port,
        [string]$PhysicalPath,
        [string]$PoolName
    )

    # Verificar si el sitio ya existe
    if (Get-Website -Name $SiteName -ErrorAction SilentlyContinue) {
        Write-Log "WARN" "[$SiteName] El sitio web ya existe. Se omite la creación."
        return
    }

    # Verificar si el puerto ya está en uso por otro sitio
    $portConflict = Get-WebBinding | Where-Object { $_.bindingInformation -like "*:${Port}:*" }
    if ($portConflict) {
        Write-Log "WARN" "[$SiteName] El puerto $Port ya está en uso por otro sitio. Se omite la creación."
        return
    }

    # Crear carpeta física si no existe
    if (-not (Test-Path $PhysicalPath)) {
        New-Item -ItemType Directory -Path $PhysicalPath -Force | Out-Null
        Write-Log "INFO" "[$SiteName] Directorio físico creado: $PhysicalPath"
    }
    else {
        Write-Log "INFO" "[$SiteName] Directorio físico ya existe: $PhysicalPath"
    }

    New-Website -Name $SiteName `
                -Port $Port `
                -PhysicalPath $PhysicalPath `
                -ApplicationPool $PoolName `
                -Force | Out-Null

    Write-Log "INFO" "[$SiteName] Sitio web creado en puerto $Port con pool '$PoolName'."
}

# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────
try {
    Initialize-Log
    Write-Log "INFO" "=== Inicio: Creación de sitios y Application Pools ==="

    Import-Module WebAdministration -ErrorAction Stop
    Write-Log "INFO" "Módulo WebAdministration cargado."

    $csvPath = Join-Path $PSScriptRoot 'sites.csv'
    if (-not (Test-Path $csvPath)) {
        Write-Log "ERROR" "No se encontró el archivo CSV en: $csvPath"
        exit 1
    }

    $sites = @(Import-Csv -Path $csvPath)
    Write-Log "INFO" "CSV cargado: $($sites.Count) sitio(s) encontrado(s) en '$csvPath'."

    $errorsFound = 0

    foreach ($site in $sites) {
        $name = $site.Name.Trim()
        $port = [int]$site.Port.Trim()
        $path = $site.PhysicalPath.Trim()

        Write-Log "INFO" "--- Procesando: $name (Puerto: $port, Ruta: $path) ---"

        try {
            New-IISAppPool -PoolName $name
            New-IISSite   -SiteName $name -Port $port -PhysicalPath $path -PoolName $name
            Write-Log "INFO" "[$name] Procesado exitosamente."
        }
        catch {
            Write-Log "ERROR" "[$name] Error durante la creación: $_"
            $errorsFound++
        }
    }

    if ($errorsFound -gt 0) {
        Write-Log "WARN" "=== Fin: Proceso completado con $errorsFound error(es). Revise el log. ==="
        exit 1
    }
    else {
        Write-Log "INFO" "=== Fin: Todos los sitios fueron procesados sin errores ==="
    }
}
catch {
    if ($Script:LogFile) {
        Write-Log "ERROR" "Error fatal en el script: $_"
    }
    else {
        Write-Error "Error fatal antes de inicializar el log: $_"
    }
    exit 1
}
