# Gritsee – Deploy Masivo Pizza Quality

## Resumen

`deploy.ps1` conecta a cada PCBox vía AnyDesk, despliega el pipeline y escribe el resultado directamente en el Excel. Corre en lotes paralelos sin que tengas que entrar a ninguna PC.

---

## Requisitos en tu computadora (la que corre el deploy)

- AnyDesk instalado en `C:\Program Files (x86)\AnyDesk\AnyDesk.exe`
- Excel instalado (el script lo usa como COM para leer/escribir)
- PowerShell 5+ (ya viene en Windows 10/11)
- AWS CLI configurado (`aws configure`) con acceso a `gritsee-ensemble`
- El archivo `google_key.json` de tu repositorio

---

## Cómo ejecutar

Abre PowerShell como **Administrador** en la carpeta `C:\Users\Davidj\Desktop\Gritsee\Configuración Pizza Quality\` y corre:

### Opción A – Solo actualizar (para las 30 ya configuradas)

```powershell
.\deploy.ps1 -ExcelFile "Base Camaras.xlsx" -BatchSize 5 -TimeoutSeconds 1800
```

Solo procesa las filas con `STATUS = conectada` y `tipo = actualizar` (o auto).

### Opción B – Configuración nueva + actualización (todas las conectadas)

```powershell
.\deploy.ps1 -ExcelFile "Base Camaras.xlsx" -BatchSize 5 -TimeoutSeconds 1800 -GoogleKeyFile "google_key.json"
```

Con `-GoogleKeyFile` envía el `google_key.json` a cada PC automáticamente.

### Opción C – Solo verificar (sin tocar nada)

```powershell
.\deploy.ps1 -ExcelFile "Base Camaras.xlsx" -VerifyOnly -TestRtsp
```

Verifica tareas, archivos, dependencias y prueba el RTSP con ffmpeg. Escribe resultado en el Excel.

### Opción D – Dry run (ver qué haría sin ejecutar)

```powershell
.\deploy.ps1 -ExcelFile "Base Camaras.xlsx" -DryRun
```

---

## Columnas del Excel que necesita deploy.ps1

| Columna | Descripción |
|---|---|
| `name` | Nombre de la sucursal |
| `slug` | pcsapi-nombre-id |
| `anydesk_id` | ID numérico de AnyDesk |
| `anydesk_pass` | Contraseña AnyDesk |
| `pc_password` | Contraseña del usuario gritseeuser1 |
| `user_cam` | Usuario de la cámara |
| `pass_cam` | Contraseña de la cámara |
| `marca` | Marca (Hikvision, Dahua, etc.) |
| `cam_ip` | IP de la cámara |
| `cam_port` | Puerto RTSP (default 554) |
| `cam_channel` | Canal (default 1) |
| `STATUS` | `conectada` = se procesa, cualquier otra = se omite |
| `accion` | `no` = se omite esa fila sin importar STATUS |
| `tipo` | `nueva`, `actualizar`, o vacío = auto-detecta |
| `rtsp_url` | Solo si marca = Manual (URL RTSP completa) |

**Columnas que escribe el script (auto-generadas):**
- `GRITSEE_STATUS` — OK / Error / Apagada / En proceso...
- `GRITSEE_ULTIMO_INTENTO` — Fecha y hora del último intento
- `GRITSEE_DETALLE` — Descripción del resultado o error

---

## Lógica de auto-detección por PC (tipo = auto)

El script remoto en cada PC decide automáticamente:

1. Revisa si existe la tarea `\Gritsee\Quality run` o el archivo `qualityrun.bat`
2. Revisa si hay videos en `Documents\qualityvids\`
3. Si cualquiera existe → modo **actualizar** (NO toca RTSP, NO reinstala cámara)
4. Si nada existe → modo **nueva** (instala todo, configura RTSP)

---

## Lógica de RTSP

- Si la PC ya tiene Quality run configurado → RTSP **no se toca nunca**
- La prueba RTSP (`-TestRtsp`) usa ffmpeg para conectarse 5 segundos a la URL del `qualityrun.bat` existente
- Si falla, el detalle queda en la columna `GRITSEE_DETALLE`

---

## Problemas comunes y soluciones

| Error | Causa | Solución |
|---|---|---|
| `Apagada` en Excel | AnyDesk no conectó (timeout) | La PC está offline o AnyDesk no está corriendo |
| `Fallo configuracion` (código 20) | Error en configure_pipeline.ps1 | Ver `Desktop\gritsee_configuracion.log` en la PC remota |
| `Fallo verificacion` (código 30) | Algo falta después de instalar | Ver `C:\pizza_pipeline\verify_pipeline.log` en la PC remota |
| Timeout 1800s | Instalación de Python/torch tarda mucho | Aumentar `-TimeoutSeconds 3600` |
| `AnyDesk no encontrado` | AnyDesk no está en el path esperado | Instalar AnyDesk en tu PC o editar `$anydeskPaths` en deploy.ps1 |

---

## Flujo completo de una corrida típica

```
deploy.ps1 lee "Base Camaras.xlsx"
  → Filtra STATUS=conectada
  → Por cada lote de 5 PCs en paralelo:
      AnyDesk.exe {id} --with-password {pass} -- powershell ...
        → Descarga ZIP de github.com/dleon-1022/pizza-pipeline
        → Detecta si es nueva o actualizar
        → Instala Python 3.13.3 + Node 22.16.0 (solo si es nueva)
        → Instala dependencias pip + npm
        → Configura RTSP / qualityrun.bat (solo si no existe)
        → Crea tareas programadas (Daily Pipeline 3am, Quality run c/15min, Delete 8:20am)
        → Corre verify_pipeline.ps1
        → Sale con código 0=OK, 20=error config, 30=error verify, 99=timeout
  → Escribe resultado en Excel y guarda
```

---

## Parámetros completos de deploy.ps1

```powershell
.\deploy.ps1
  -ExcelFile "Base Camaras.xlsx"   # archivo Excel (default: pcs.xlsx)
  -BatchSize 5                      # PCs en paralelo (default: 5)
  -TimeoutSeconds 1800              # timeout por PC en segundos (default: 1800)
  -DryRun                           # no ejecuta, solo muestra qué haría
  -VerifyOnly                       # solo verifica, no configura
  -AllRows                          # procesa todas las filas, no solo STATUS=conectada
  -TestRtsp                         # prueba conexión RTSP con ffmpeg
  -RunPipelineTest                  # ejecuta run_pipeline.bat al final
  -KeepLegacyFolder                 # no elimina C:\pizza-pipeline antigua
  -GoogleKeyFile "google_key.json"  # envía google_key.json a cada PC
```
