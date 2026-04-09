#Requires -RunAsAdministrator
#Requires -Modules WebAdministration

<#
.SYNOPSIS
    Modifica los Application Pool Defaults de IIS.

.DESCRIPTION
    Configura a nivel global (Application Pool Defaults) los siguientes valores:
      - Process Model > Idle Time Out   : 0 (deshabilitado)
      - Process Model > Identity        : SpecificUser (usuario/contraseña desde .env)
      - Recycling > Regular Time Interval: 0 (deshabilitado)
      - Start Mode                       : AlwaysRunning

.NOTES
    Requiere el archivo .env en el mismo directorio con las variables:
      IIS_USER=DOMAIN\ServiceAccount
      IIS_PASSWORD=YourPassword
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
    $Script:LogFile = Join-Path $logsDir "set_default_pool_settings_$timestamp.log"
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
# Lectura del archivo .env
# ─────────────────────────────────────────────
function Read-EnvFile {
    param([string]$EnvPath)

    if (-not (Test-Path $EnvPath)) {
        Write-Log "ERROR" "No se encontró el archivo .env en: $EnvPath"
        throw "Archivo .env requerido no encontrado."
    }

    $env = @{}
    Get-Content $EnvPath | ForEach-Object {
        $line = $_.Trim()
        # Ignorar líneas vacías y comentarios
        if ($line -and $line -notmatch '^\s*#') {
            $parts = $line -split '=', 2
            if ($parts.Count -eq 2) {
                $env[$parts[0].Trim()] = $parts[1].Trim()
            }
        }
    }

    foreach ($key in @('IIS_USER', 'IIS_PASSWORD')) {
        if (-not $env.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($env[$key])) {
            Write-Log "ERROR" "La variable '$key' no está definida o está vacía en el archivo .env."
            throw "Variable '$key' requerida no encontrada en .env."
        }
    }

    return $env
}

# ─────────────────────────────────────────────
# Aplicar configuración de Application Pool Defaults
# ─────────────────────────────────────────────
function Set-AppPoolDefaults {
    param(
        [string]$IISUser,
        [string]$IISPassword
    )

    Write-Log "INFO" "Aplicando configuración a Application Pool Defaults en IIS..."

    try {
        # Process Model > Idle Time Out = 0 (deshabilitado)
        Set-WebConfigurationProperty `
            -pspath 'MACHINE/WEBROOT/APPHOST' `
            -filter 'system.applicationHost/applicationPools/applicationPoolDefaults/processModel' `
            -name 'idleTimeout' `
            -value ([TimeSpan]::Zero)
        Write-Log "INFO" "processModel.idleTimeout establecido en 00:00:00 (deshabilitado)."

        # Process Model > Identity = SpecificUser
        Set-WebConfigurationProperty `
            -pspath 'MACHINE/WEBROOT/APPHOST' `
            -filter 'system.applicationHost/applicationPools/applicationPoolDefaults/processModel' `
            -name 'identityType' `
            -value 3   # 3 = SpecificUser
        Write-Log "INFO" "processModel.identityType establecido en SpecificUser."

        Set-WebConfigurationProperty `
            -pspath 'MACHINE/WEBROOT/APPHOST' `
            -filter 'system.applicationHost/applicationPools/applicationPoolDefaults/processModel' `
            -name 'userName' `
            -value $IISUser
        Write-Log "INFO" "processModel.userName establecido en '$IISUser'."

        Set-WebConfigurationProperty `
            -pspath 'MACHINE/WEBROOT/APPHOST' `
            -filter 'system.applicationHost/applicationPools/applicationPoolDefaults/processModel' `
            -name 'password' `
            -value $IISPassword
        Write-Log "INFO" "processModel.password actualizado."

        # Recycling > Regular Time Interval = 0 (deshabilitado)
        Set-WebConfigurationProperty `
            -pspath 'MACHINE/WEBROOT/APPHOST' `
            -filter 'system.applicationHost/applicationPools/applicationPoolDefaults/recycling/periodicRestart' `
            -name 'time' `
            -value ([TimeSpan]::Zero)
        Write-Log "INFO" "recycling.periodicRestart.time establecido en 00:00:00 (deshabilitado)."

        # Start Mode = AlwaysRunning
        Set-WebConfigurationProperty `
            -pspath 'MACHINE/WEBROOT/APPHOST' `
            -filter 'system.applicationHost/applicationPools/applicationPoolDefaults' `
            -name 'startMode' `
            -value 'AlwaysRunning'
        Write-Log "INFO" "startMode establecido en AlwaysRunning."

        Write-Log "INFO" "Configuración de Application Pool Defaults aplicada exitosamente."
    }
    catch {
        Write-Log "ERROR" "Error al aplicar configuración: $_"
        throw
    }
}

# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────
try {
    Initialize-Log

    Write-Log "INFO" "=== Inicio: Configuración de Application Pool Defaults ==="

    Import-Module WebAdministration -ErrorAction Stop
    Write-Log "INFO" "Módulo WebAdministration cargado."

    $envPath = Join-Path $PSScriptRoot '.env'
    $envVars = Read-EnvFile -EnvPath $envPath

    Set-AppPoolDefaults -IISUser $envVars['IIS_USER'] -IISPassword $envVars['IIS_PASSWORD']

    Write-Log "INFO" "=== Fin: Configuración completada sin errores ==="
}
catch {
    if ($Script:LogFile) {
        Write-Log "ERROR" "El script finalizó con errores: $_"
    }
    else {
        Write-Error "Error fatal antes de inicializar el log: $_"
    }
    exit 1
}
