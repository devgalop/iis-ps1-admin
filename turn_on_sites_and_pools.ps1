#Requires -RunAsAdministrator
#Requires -Modules WebAdministration

<#
.SYNOPSIS
    Enciende los Application Pools y sitios web de IIS, y ejecuta las URLs de activación.

.DESCRIPTION
    Lee un archivo CSV con las columnas SiteName, TurnOnURL, TurnOffURL.

    Para cada registro:
      1. Valida que el Application Pool con nombre SiteName existe en IIS.
      2. Si el Application Pool no está iniciado, lo inicia.
      3. Si el sitio web no está iniciado, lo inicia.
      4. Espera 5 segundos.
      5. Ejecuta un GET a TurnOnURL y registra el resultado.

    El procesamiento continúa con los demás registros si uno falla.

.PARAMETER CsvPath
    Ruta al archivo CSV con las columnas SiteName, TurnOnURL, TurnOffURL.

.EXAMPLE
    .\turn_on_sites_and_pools.ps1 -CsvPath ".\sites\sites-prod.csv"
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
    $Script:LogFile = Join-Path $logsDir "turn_on_sites_and_pools_$timestamp.log"
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
# Main
# ─────────────────────────────────────────────
try {
    Initialize-Log

    Write-Log "INFO" "=== Inicio: Encendido de sitios y Application Pools ==="
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
        $siteName  = $site.SiteName.Trim()
        $turnOnUrl = $site.TurnOnURL.Trim()

        Write-Log "INFO" "--- Procesando: $siteName ---"

        try {
            # Validar que el Application Pool existe
            if (-not (Test-Path "IIS:\AppPools\$siteName")) {
                Write-Log "ERROR" "[$siteName] El Application Pool no existe en IIS. Se omite."
                $errorsFound++
                continue
            }

            # Iniciar Application Pool si no está corriendo
            $poolState = (Get-WebAppPoolState -Name $siteName).Value
            if ($poolState -ne 'Started') {
                Start-WebAppPool -Name $siteName
                Write-Log "INFO" "[$siteName] Application Pool iniciado (estaba en estado '$poolState')."
            }
            else {
                Write-Log "INFO" "[$siteName] Application Pool ya estaba iniciado."
            }

            # Iniciar sitio web si no está corriendo
            $website = Get-Website -Name $siteName -ErrorAction SilentlyContinue
            if ($website) {
                $siteState = (Get-WebsiteState -Name $siteName).Value
                if ($siteState -ne 'Started') {
                    Start-Website -Name $siteName
                    Write-Log "INFO" "[$siteName] Sitio web iniciado (estaba en estado '$siteState')."
                }
                else {
                    Write-Log "INFO" "[$siteName] Sitio web ya estaba iniciado."
                }
            }
            else {
                Write-Log "WARN" "[$siteName] No se encontró un sitio web con este nombre en IIS."
            }

            # Pausa de 5 segundos antes de llamar la URL
            Write-Log "INFO" "[$siteName] Esperando 5 segundos antes de llamar TurnOnURL..."
            Start-Sleep -Seconds 5

            # GET a TurnOnURL
            Write-Log "INFO" "[$siteName] Ejecutando GET a: $turnOnUrl"
            try {
                $response = Invoke-WebRequest -Uri $turnOnUrl -Method GET -UseBasicParsing -ErrorAction Stop
                Write-Log "INFO" "[$siteName] GET completado. Código de respuesta: $($response.StatusCode)."
            }
            catch {
                Write-Log "ERROR" "[$siteName] Error al ejecutar GET a '$turnOnUrl': $_"
                $errorsFound++
            }

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
