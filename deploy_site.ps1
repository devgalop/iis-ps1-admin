#Requires -RunAsAdministrator
#Requires -Modules WebAdministration

<#
.SYNOPSIS
    Realiza el deploy de un sitio IIS con backup previo.

.DESCRIPTION
    Proceso:
      1. Detiene el Application Pool del sitio.
      2. Detiene el sitio web.
      3. Copia la carpeta actual del sitio como backup en {PhysicalPath}_backup\backup_{timestamp}.
      4. Limpia el contenido del directorio del sitio.
      5. Copia el contenido de SourcePath al directorio del sitio.
      6. Inicia el sitio web.
      7. Inicia el Application Pool.

.PARAMETER SiteName
    Nombre del sitio web en IIS (debe existir).

.PARAMETER SourcePath
    Ruta a la carpeta con los archivos de publicación nuevos.

.EXAMPLE
    .\deploy_site.ps1 -SiteName "MySite" -SourcePath "C:\Releases\MySite_v2"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SiteName,

    [Parameter(Mandatory = $true)]
    [string]$SourcePath
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
    $Script:LogFile = Join-Path $logsDir "deploy_site_${SiteName}_$timestamp.log"
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
        Write-Log "INFO" "[$SiteName] El Application Pool '$PoolName' ya está detenido."
        return
    }

    Stop-WebAppPool -Name $PoolName
    Write-Log "INFO" "[$SiteName] Deteniendo Application Pool '$PoolName'..."

    $maxWait  = 30   # segundos máximos de espera
    $elapsed  = 0
    $interval = 2

    while ($elapsed -lt $maxWait) {
        Start-Sleep -Seconds $interval
        $elapsed += $interval
        $state = (Get-WebAppPoolState -Name $PoolName).Value
        if ($state -eq 'Stopped') {
            Write-Log "INFO" "[$SiteName] Application Pool '$PoolName' detenido (${elapsed}s)."
            return
        }
    }

    Write-Log "WARN" "[$SiteName] Application Pool '$PoolName' no se detuvo en ${maxWait}s. Estado actual: $state"
}

# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────
$siteStarted = $false
$poolStarted  = $false

try {
    Initialize-Log

    Write-Log "INFO" "=== Inicio: Deploy de '$SiteName' ==="
    Write-Log "INFO" "Origen: $SourcePath"

    Import-Module WebAdministration -ErrorAction Stop
    Write-Log "INFO" "Módulo WebAdministration cargado."

    # ── Validaciones previas ───────────────────
    if (-not (Test-Path $SourcePath)) {
        Write-Log "ERROR" "La ruta de origen no existe: $SourcePath"
        exit 1
    }

    $website = Get-Website -Name $SiteName -ErrorAction SilentlyContinue
    if (-not $website) {
        Write-Log "ERROR" "El sitio '$SiteName' no existe en IIS."
        exit 1
    }

    $poolName = $website.applicationPool
    if (-not (Test-Path "IIS:\AppPools\$poolName")) {
        Write-Log "ERROR" "El Application Pool '$poolName' asociado al sitio no existe en IIS."
        exit 1
    }

    $physicalPath = $website.physicalPath
    Write-Log "INFO" "Ruta física del sitio: $physicalPath"
    Write-Log "INFO" "Application Pool: $poolName"

    # ── 1. Detener pool ────────────────────────
    Write-Log "INFO" "--- Paso 1/6: Deteniendo Application Pool ---"
    Stop-IISAppPoolSafe -PoolName $poolName

    # ── 2. Detener sitio ──────────────────────
    Write-Log "INFO" "--- Paso 2/6: Deteniendo sitio web ---"
    $siteState = (Get-WebsiteState -Name $SiteName).Value
    if ($siteState -ne 'Stopped') {
        Stop-Website -Name $SiteName
        Write-Log "INFO" "[$SiteName] Sitio web detenido."
    }
    else {
        Write-Log "INFO" "[$SiteName] El sitio ya estaba detenido."
    }

    # ── 3. Backup ─────────────────────────────
    Write-Log "INFO" "--- Paso 3/6: Realizando backup ---"
    $backupTimestamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $backupRoot = "${physicalPath}_backup"
    $backupDest = Join-Path $backupRoot "backup_$backupTimestamp"

    if (-not (Test-Path $backupRoot)) {
        New-Item -ItemType Directory -Path $backupRoot | Out-Null
    }

    if (Test-Path $physicalPath) {
        Copy-Item -Path $physicalPath -Destination $backupDest -Recurse -Force
        Write-Log "INFO" "[$SiteName] Backup creado en: $backupDest"
    }
    else {
        Write-Log "WARN" "[$SiteName] La ruta física '$physicalPath' no existe. No se creó backup."
    }

    # ── 4. Limpiar destino ────────────────────
    Write-Log "INFO" "--- Paso 4/6: Limpiando directorio destino ---"
    if (Test-Path $physicalPath) {
        Get-ChildItem -Path $physicalPath -Force | Remove-Item -Recurse -Force
        Write-Log "INFO" "[$SiteName] Contenido de '$physicalPath' eliminado."
    }
    else {
        New-Item -ItemType Directory -Path $physicalPath -Force | Out-Null
        Write-Log "INFO" "[$SiteName] Directorio destino creado: $physicalPath"
    }

    # ── 5. Copiar publicación nueva ───────────
    Write-Log "INFO" "--- Paso 5/6: Copiando archivos de publicación ---"
    Copy-Item -Path (Join-Path $SourcePath '*') -Destination $physicalPath -Recurse -Force
    Write-Log "INFO" "[$SiteName] Archivos copiados desde '$SourcePath' a '$physicalPath'."

    # ── 6. Iniciar sitio ──────────────────────
    Write-Log "INFO" "--- Paso 6/6: Iniciando sitio web y Application Pool ---"
    Start-Website -Name $SiteName
    $siteStarted = $true
    Write-Log "INFO" "[$SiteName] Sitio web iniciado."

    Start-WebAppPool -Name $poolName
    $poolStarted = $true
    Write-Log "INFO" "[$SiteName] Application Pool '$poolName' iniciado."

    Write-Log "INFO" "=== Fin: Deploy de '$SiteName' completado exitosamente ==="
}
catch {
    if ($Script:LogFile) {
        Write-Log "ERROR" "Error durante el deploy: $_"
        Write-Log "INFO" "Intentando restaurar el estado del sitio y pool..."

        try {
            if (-not $siteStarted) {
                Start-Website -Name $SiteName -ErrorAction SilentlyContinue
                Write-Log "INFO" "[$SiteName] Sitio web iniciado en recuperación de error."
            }
            if (-not $poolStarted) {
                Start-WebAppPool -Name (Get-Website -Name $SiteName).applicationPool -ErrorAction SilentlyContinue
                Write-Log "INFO" "[$SiteName] Application Pool iniciado en recuperación de error."
            }
        }
        catch {
            Write-Log "ERROR" "No se pudo restaurar el estado del sitio/pool: $_"
        }
    }
    else {
        Write-Error "Error fatal antes de inicializar el log: $_"
    }
    exit 1
}
