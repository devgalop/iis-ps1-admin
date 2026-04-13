# Administración de IIS con PowerShell

Este proyecto es una colección de scripts utiles para administrar IIS. Estos scripts permiten la configuración de valores por defecto, la creación de sitios y pools de aplicaciones y emula un tipo de despliegue continuo para aplicaciones web en IIS.

## Scripts disponibles

- `set_default_values.ps1`: Configura valores por defecto para nuevos sitios y pools de aplicaciones.
- `create_sites_and_pools.ps1`: Crea sitios y pools de aplicaciones a partir de un archivo CSV.
- `deploy_app.ps1`: Emula un despliegue continuo para aplicaciones web en IIS.
- `turn_on_sites_and_pools.ps1`: Enciende los sitios y pools de aplicaciones creados.
- `turn_off_sites_and_pools.ps1`: Apaga los sitios y pools de aplicaciones creados.

## Prerequisitos

- PowerShell 5.1 o superior
- IIS instalado y configurado en el sistema
- Permisos de administrador para ejecutar los scripts
- Archivo CSV con la configuración de los sitios y pools de aplicaciones (para `create_sites_and_pools.ps1`)
- Archivo .env con las variables de entorno necesarias para la configuración (para `set_default_values.ps1`)
- Archivo CSV con la configuración de encendido y apagado de sitios y pools de aplicaciones (para `turn_on_sites_and_pools.ps1` y `turn_off_sites_and_pools.ps1`)

## Uso

- Dentro del servidor que contiene el IIS, debes crear una carpeta para alojar los scripts y los archivos de configuración. Por ejemplo : `C:\IIS_Administration`

  ```bash
    mkdir C:\IIS_Administration
  ```

- Copia los scripts y los archivos de configuración a la carpeta creada.

- Para la ejecución de los scripts, abre PowerShell con permisos de administrador y navega a la carpeta donde se encuentran los scripts.

  ```bash
    cd C:\IIS_Administration
  ```

- Ejecuta el script deseado. Por ejemplo, para configurar los valores por defecto:

  ```bash
    .\set_default_values.ps1
  ```

## Ejecución de script set_default_values.ps1

El script `set_default_values.ps1` lee las variables de entorno desde un archivo `.env` y configura los valores por defecto para nuevos sitios y pools de aplicaciones en IIS. Asegúrate de tener un archivo `.env` con las variables necesarias antes de ejecutar el script.

El archivo `.env` debe contener las siguientes variables:

```env
# Formato: KEY=VALUE (sin comillas, sin espacios alrededor del =)
IIS_USER=DOMAIN\ServiceAccount
IIS_PASSWORD=YourSecurePasswordHere
```

Para ejecutar el script, simplemente ejecuta el siguiente comando en PowerShell:

```bash
.\set_default_values.ps1
```

## Ejecución de script create_sites_and_pools.ps1

El script `create_sites_and_pools.ps1` crea sitios y pools de aplicaciones en IIS a partir de un archivo CSV. Asegúrate de tener un archivo CSV `sites.csv` con la configuración de los sitios y pools de aplicaciones antes de ejecutar el script.

El archivo `sites.csv` debe contener las siguientes columnas:

```csv
Name,Port,PhysicalPath
Example,8080,C:\inetpub\wwwroot\Example
```

- `Name`: El nombre del sitio y pool de aplicaciones.
- `Port`: El puerto en el que el sitio escuchará.
- `PhysicalPath`: La ruta física donde se encuentran los archivos del sitio.

Para ejecutar el script, simplemente ejecuta el siguiente comando en PowerShell:

```bash
.\create_sites_and_pools.ps1
```

## Ejecución de script deploy_app.ps1

El script `deploy_app.ps1` emula un despliegue continuo para aplicaciones web en IIS. Este script puede ser utilizado para automatizar el proceso de despliegue de una aplicación web en IIS, incluyendo la copia de archivos, la configuración de permisos y la reiniciación del sitio.

Es importante tener en cuenta que previamente deben existir:

- El sitio y pool de aplicaciones en IIS donde se desplegará la aplicación.
- La aplicación web debe estar lista para ser desplegada, con los archivos necesarios en una ubicación accesible.

Para ejecutar el script, simplemente ejecuta el siguiente comando en PowerShell:

```bash
.\deploy_app.ps1 -SiteName "Example" -SourcePath "C:\Path\To\You\App\Modified"
```

- `-SiteName`: El nombre del sitio en IIS donde se desplegará la aplicación.
- `-SourcePath`: La ruta de origen donde se encuentran los archivos de la aplicación que se van a desplegar.

**NOTA**: La ruta de destino para la aplicación se determinará automáticamente a partir de la configuración del sitio en IIS.

## Ejecución de scripts turn_on_sites_and_pools.ps1 y turn_off_sites_and_pools.ps1

Los scripts `turn_on_sites_and_pools.ps1` y `turn_off_sites_and_pools.ps1` permiten encender y apagar los sitios y pools de aplicaciones creados en IIS a partir de un archivo CSV. Asegúrate de tener un archivo CSV `sites_status.csv` con la configuración de los sitios y pools de aplicaciones antes de ejecutar los scripts.

El archivo `sites_status.csv` debe contener las siguientes columnas:

```csv
SiteName,TurnOnURL,TurnOffURL
Example,http://localhost:8080/turnon,http://localhost:8080/turnoff
```

- `SiteName`: El nombre del sitio en IIS.
- `TurnOnURL`: La URL que se utilizará para encender el sitio y pool de aplicaciones.
- `TurnOffURL`: La URL que se utilizará para apagar el sitio y pool de aplicaciones.

Para ejecutar el script de encendido, simplemente ejecuta el siguiente comando en PowerShell:

```bash
# La variable CsvPath debe apuntar al archivo CSV con la configuración de los sitios y pools de aplicaciones
.\turn_on_sites_and_pools.ps1 -CsvPath "C:\IIS_Administration\sites_status.csv"
```

Para ejecutar el script de apagado, simplemente ejecuta el siguiente comando en PowerShell:

```bash
# La variable CsvPath debe apuntar al archivo CSV con la configuración de los sitios y pools de aplicaciones
.\turn_off_sites_and_pools.ps1 -CsvPath "C:\IIS_Administration\sites_status.csv"
```

## Revision de logs

Todos los scripts generan logs detallados de su ejecución. Cada log se genera en la carpeta `logs` dentro del directorio que contine los scripts. Los logs incluyen información sobre las acciones realizadas, errores encontrados y resultados de la ejecución.
