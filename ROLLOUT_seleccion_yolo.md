# Rollout: selección con YOLO (sin ResNet)

## Qué cambia

| | Antes | Ahora |
|---|---|---|
| Paso 2 | `classify_frames.py` (ResNet, umbral 0.30) | eliminado |
| Paso 3 | `crop_pizza_images.py` sobre `selected_frames` | `select_crops_yolo.py` sobre **todos** los frames |
| Criterio de selección | probabilidad del ResNet | confianza del YOLO que hace el crop |
| Relleno | frames aleatorios hasta 100-150, sin pasar por ningún modelo | **no hay relleno** |
| Duplicados | sin control | dedup por IoU ≥ 0.60 en ventana de 3 frames (60 s) |
| Pasos 1, 4, 5, 6 | — | **sin cambios** |

**Verificado en el repo:** `upload_selected_frames.js` línea 8 lee
`C:\pizza_pipeline\cropped_frames` y sube *todo* lo que encuentre ahí. El script nuevo
escribe en esa misma carpeta con los mismos nombres (`<video>_frame_NNNN_<idx>.png`), así
que el tope de 150 controla directamente lo que llega a S3 y a Sheets. El `video` que
aparece en el CSV sale de `f.split("_frame_")[0]`, que sigue funcionando con estos nombres.

`selected_frames` **no** se sube; el script igual deja ahí los frames de origen como
referencia visual, igual que antes.

---

## 1. Push desde tu equipo

### Ojo antes de hacer `git add -A`

El working tree tiene 9 archivos modificados, pero **6 son solo cambio de fin de línea**
(CRLF↔LF), sin cambios reales de contenido:

```
extract_frames.py   requirements.txt   upload_selected_frames.js
run_pipeline.bat    movesnaps.bat      movesnaps.js
```

Cambios reales pendientes que **no** son de esta tarea:

- `.gitignore` → agrega `pipeline_simple/`
- `upload_to_sheets.js` → 15 líneas
- `setup.ps1` → formato del slug sin el sufijo hex

Si haces `git add -A` te vas a llevar todo eso junto y el diff queda ilegible. Commitea
solo lo de esta tarea:

```bat
cd /d "C:\Users\Davidj\Desktop\Gritsee\Configuración Pizza Quality"

git add .gitattributes .gitignore run_pipeline.bat scripts\select_crops_yolo.py
git add run_test_crop_only.bat scripts\test_crop_only.py ROLLOUT_seleccion_yolo.md

git commit -m "seleccion YOLO sin ResNet, activable por box con use_crop_only.enabled"

git push origin main
```

### Por qué se agrega `.gitattributes`

`run_pipeline.bat` usa `goto`, y **cmd.exe falla en los `goto` cuando el .bat tiene
finales de línea Unix** ("no se encuentra la etiqueta del lote"). El repo no tenía
`.gitattributes` ni `core.autocrlf`, que es justo la causa de la churn de arriba. Con

```
*.bat text eol=crlf
*.ps1 text eol=crlf
```

los `.bat` y `.ps1` siempre llegan a los box con CRLF, pase lo que pase.

---

## 2. En cada PCBOX

`C:\pizza_pipeline` es un clon del repo (`setup.ps1` se corre *después* de clonar y no
hace `pull` por su cuenta), así que actualizar un box es traer el commit y nada más.

### 2.1 Traer el código

```bat
cd /d C:\pizza_pipeline
git status
```

Si `git status` muestra archivos modificados (lo más probable es que sea la misma churn
de fin de línea), descártalos y traé la versión nueva:

```bat
git fetch origin
git reset --hard origin/main
```

`reset --hard` borra los cambios locales de archivos **versionados**. No toca
`location_slug.txt`, `google_key.json`, `processed_videos.txt` ni las carpetas de trabajo,
porque están en `.gitignore`. Si en `git status` ves algún archivo modificado que
reconozcas como un ajuste hecho a mano en ese box, guárdalo antes con `git stash`.

### 2.2 Corrida en seco, ANTES de activar

No escribe imágenes, no sube nada, no marca videos:

```bat
cd /d C:\pizza_pipeline
python scripts\select_crops_yolo.py --dry_run --report_html
```

Revisa en la salida:

- **Crops detectados** vs **duplicados descartados** vs **seleccionados**
- El reparto por video (que no se lo lleve una sola cámara)
- La confianza media

Abre `C:\pizza_pipeline\reporte_seleccion.html` y mira las imágenes de **menor**
confianza, que son las que definen si 0.45 es el umbral correcto. Si ahí hay recortes que
no son pizza, sube `--conf` antes de activar.

Necesita frames en `C:\pizza_pipeline\frames`. Si están vacíos porque el pipeline ya
corrió y limpió, extrae primero con `python scripts\extract_frames.py`.

### 2.3 Activar el box

```bat
echo. > C:\pizza_pipeline\use_crop_only.enabled
```

Y para volver atrás, en cualquier momento:

```bat
del C:\pizza_pipeline\use_crop_only.enabled
```

`run_pipeline.bat` bifurca según ese archivo. `classify_frames.py` y
`crop_pizza_images.py` siguen en el repo, así que el rollback es borrar un archivo: sin
git, sin redeploy, sin reinstalar nada. El archivo está en `.gitignore`, así que `main`
queda idéntico para todos los box.

### 2.4 Al día siguiente

```bat
type C:\pizza_pipeline\pipeline.log
type C:\pizza_pipeline\historial_selecciones.csv
```

En el log debe decir `Modo: SELECCION YOLO (sin ResNet)`.

---

## 3. Orden recomendado

1. Push a `main`
2. **Un solo box**: pasos 2.1 → 2.2 → 2.3
3. Dejarlo 2-3 días y comparar `historial_selecciones.csv` contra un box que siga en ResNet
4. Si se ve bien, repetir 2.1 → 2.2 → 2.3 en el resto

---

## Parámetros que vale la pena tocar

| Parámetro | Default | Cuándo cambiarlo |
|---|---|---|
| `--conf` | 0.45 | Súbelo si aparecen recortes que no son pizza; bájalo si no llega a 100 imágenes |
| `--target_min` / `--target_max` | 100 / 150 | Si quieres más o menos volumen diario |
| `--max_per_video` | 30 | Si una cámara u hora domina la selección |
| `--dedup_iou` | 0.60 | Súbelo (0.75) si descarta pizzas distintas que están cerca; bájalo si siguen pasando repetidas |
| `--dedup_window` | 3 frames (60 s) | Súbelo si las pizzas se quedan mucho tiempo en cámara |
| `--fail_under` | 0 (desactivado) | Ponlo en ~50 si prefieres que el pipeline **falle** antes que subir un día flojo |

Los defaults están escritos en `run_pipeline.bat`, en el bloque `:seleccion_yolo`.

---

## Diferencias de comportamiento a tener presentes

- **Ya no hay relleno aleatorio.** Un día de poca actividad va a dar menos de 100
  imágenes y una advertencia en el log. Antes el conteo llegaba a 100-150 siempre, aunque
  el modelo hubiera fallado. Es intencional: preferible ver el bajón que esconderlo.
- **El objetivo es 150, no un número al azar entre 100 y 150.** El script viejo sorteaba
  el total con `random.randint`; este toma las mejores hasta 150 y avisa si no llega a 100.
- **Una pizza quieta mucho tiempo** ya no genera 6 imágenes casi idénticas, sino
  aproximadamente una por ventana de 60 s.

---

## Detalle aparte, sin relación con esto

`setup.ps1` línea 14 apunta a `https://github.com/dleon-1022/pizza-pipeline.git` (con
guion) pero el `origin` real del repo es `pizza_pipeline.git` (con guion bajo). Si el repo
se renombró, GitHub redirige y el clone funciona igual; si no, el `setup.ps1` de un box
nuevo falla al clonar. Vale confirmarlo antes del próximo box desde cero.
