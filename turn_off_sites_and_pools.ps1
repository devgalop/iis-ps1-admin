#Requires -RunAsAdministrator
#Requires -Modules WebAdministration

<#
.SYNOPSIS
    Ejecuta las URLs de desactivación y detiene los Application Pools y sitios web de IIS.

.DESCRIPTION
    Lee un archivo CSV con las columnas SiteName, TurnOnURL, TurnOffURL.

    Para cada registro evalúa el estado del Application Pool y el sitio web:

      - Pool detenido y sitio detenido  → ya está apagado, se omite.
      - Sitio detenido y pool encendido → se detiene solo el pool.
      - Pool y sitio encendidos         → ejecuta GET a TurnOffURL, espera 15 segundos,
                                          luego detiene el sitio y el pool.

    El procesamiento continúa con los demás registros si uno falla.

.PARAMETER CsvPath
    Ruta al archivo CSV con las columnas SiteName, TurnOnURL, TurnOffURL.

.EXAMPLE
    .\turn_off_sites_and_pools.ps1 -CsvPath ".\sites\sites-prod.csv"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath
)

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
    $Script:LogFile = Join-Path $logsDir "turn_off_sites_and_pools_$timestamp.log"
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
# Detener pool con espera
# ─────────────────────────────────────────────
function Stop-IISAppPoolSafe {
    param([string]$PoolName)

    $pool = Get-WebAppPoolState -Name $PoolName
    if ($pool.Value -eq 'Stopped') {
        Write-Log "INFO" "[$PoolName] El Application Pool ya está detenido."
        return
    }

    Stop-WebAppPool -Name $PoolName
    Write-Log "INFO" "[$PoolName] Deteniendo Application Pool '$PoolName'..."

    $maxWait  = 30   # segundos máximos de espera
    $elapsed  = 0
    $interval = 2

    while ($elapsed -lt $maxWait) {
        Start-Sleep -Seconds $interval
        $elapsed += $interval
        $state = (Get-WebAppPoolState -Name $PoolName).Value
        if ($state -eq 'Stopped') {
            Write-Log "INFO" "[$PoolName] Application Pool '$PoolName' detenido (${elapsed}s)."
            return
        }
    }

    Write-Log "WARN" "[$PoolName] Application Pool '$PoolName' no se detuvo en ${maxWait}s. Estado actual: $state"
}

# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────
try {
    Initialize-Log

    Write-Log "INFO" "=== Inicio: Apagado de sitios y Application Pools ==="
    Write-Log "INFO" "CSV: $CsvPath"

    Import-Module WebAdministration -ErrorAction Stop
    Write-Log "INFO" "Módulo WebAdministration cargado."

    if (-not (Test-Path $CsvPath)) {
        Write-Log "ERROR" "No se encontró el archivo CSV en: $CsvPath"
        exit 1
    }

    $sites = @(Import-Csv -Path $CsvPath)
    Write-Log "INFO" "CSV cargado: $($sites.Count) sitio(s) encontrado(s) en '$CsvPath'."

    $errorsFound = 0

    foreach ($site in $sites) {
        $siteName   = $site.SiteName.Trim()
        $turnOffUrl = $site.TurnOffURL.Trim()

        Write-Log "INFO" "--- Procesando: $siteName ---"

        try {
            # Validar que el Application Pool existe
            if (-not (Test-Path "IIS:\AppPools\$siteName")) {
                Write-Log "ERROR" "[$siteName] El Application Pool no existe en IIS. Se omite."
                $errorsFound++
                continue
            }

            $poolState = (Get-WebAppPoolState -Name $siteName).Value
            $website   = Get-Website -Name $siteName -ErrorAction SilentlyContinue
            $siteState = if ($website) { (Get-WebsiteState -Name $siteName).Value } else { 'Stopped' }

            # Escenario 1: pool y sitio apagados → ya está apagado, se omite
            if ($poolState -eq 'Stopped' -and $siteState -eq 'Stopped') {
                Write-Log "INFO" "[$siteName] El Application Pool y el sitio web ya están detenidos. Se omite."
                continue
            }

            # Escenario 2: sitio apagado pero pool encendido → apagar solo el pool
            if ($siteState -eq 'Stopped' -and $poolState -ne 'Stopped') {
                Write-Log "INFO" "[$siteName] El sitio web está detenido pero el pool está en estado '$poolState'. Deteniendo pool..."
                Stop-IISAppPoolSafe -PoolName $siteName
                Write-Log "INFO" "[$siteName] Procesado exitosamente."
                continue
            }

            # Escenario 3: pool y sitio encendidos → GET, esperar 15s, apagar sitio y pool
            Write-Log "INFO" "[$siteName] Application Pool en estado '$poolState', sitio web en estado '$siteState'."

            # GET a TurnOffURL
            Write-Log "INFO" "[$siteName] Ejecutando GET a: $turnOffUrl"
            try {
                $response = Invoke-WebRequest -Uri $turnOffUrl -Method GET -UseBasicParsing -ErrorAction Stop
                Write-Log "INFO" "[$siteName] GET completado. Código de respuesta: $($response.StatusCode)."
            }
            catch {
                Write-Log "ERROR" "[$siteName] Error al ejecutar GET a '$turnOffUrl': $_"
                $errorsFound++
            }

            # Pausa de 15 segundos antes de detener el sitio y el pool
            Write-Log "INFO" "[$siteName] Esperando 15 segundos antes de detener el sitio y el pool..."
            Start-Sleep -Seconds 15

            # Detener sitio web
            if ($website) {
                $currentSiteState = (Get-WebsiteState -Name $siteName).Value
                if ($currentSiteState -ne 'Stopped') {
                    Stop-Website -Name $siteName
                    Write-Log "INFO" "[$siteName] Sitio web detenido."
                }
                else {
                    Write-Log "INFO" "[$siteName] El sitio web ya estaba detenido."
                }
            }

            # Detener Application Pool con espera
            Stop-IISAppPoolSafe -PoolName $siteName

            Write-Log "INFO" "[$siteName] Procesado exitosamente."
        }
        catch {
            Write-Log "ERROR" "[$siteName] Error inesperado durante el procesamiento: $_"
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
