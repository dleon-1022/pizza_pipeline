# generar_deploy_key.ps1
# Corre este script UNA SOLA VEZ en tu PC.
# Genera el par de claves SSH para que las 200 PCs puedan clonar el repo privado.

$keyPath = "$env:USERPROFILE\Desktop\pizza_deploy_key"

Write-Host ""
Write-Host "  ============================================================"
Write-Host "    GRITSEE - Generando Deploy Key para GitHub"
Write-Host "  ============================================================"
Write-Host ""

# Verificar que ssh-keygen esta disponible
if (-not (Get-Command ssh-keygen -ErrorAction SilentlyContinue)) {
    Write-Host "  ERROR: ssh-keygen no encontrado."
    Write-Host "  Instala Git para Windows primero: https://git-scm.com"
    pause
    exit 1
}

# Generar par de claves ed25519
Write-Host "  Generando clave SSH..."
ssh-keygen -t ed25519 -C "gritsee-pcbox-deploy" -f $keyPath -N '""' | Out-Null

if (-not (Test-Path "$keyPath.pub")) {
    Write-Host "  ERROR: No se pudo generar la clave."
    pause
    exit 1
}

$pubKey = Get-Content "$keyPath.pub" -Raw

cls
Write-Host ""
Write-Host "  ============================================================"
Write-Host "    PASO 1 - Agrega esta clave a GitHub"
Write-Host "  ============================================================"
Write-Host ""
Write-Host "  Ve a este enlace:"
Write-Host "  https://github.com/dleon-1022/PC-configuration/settings/keys/new"
Write-Host ""
Write-Host "  Rellena el formulario:"
Write-Host "    Title:            pcbox-deploy"
Write-Host "    Key:              (pega lo de abajo)"
Write-Host "    Allow write:      NO marques esta opcion"
Write-Host ""
Write-Host "  ---- COPIA ESTA CLAVE PUBLICA ----"
Write-Host ""
Write-Host $pubKey
Write-Host "  ----------------------------------"
Write-Host ""

# Copiar al portapapeles automaticamente
$pubKey | Set-Clipboard
Write-Host "  (Ya se copio automaticamente al portapapeles)"
Write-Host ""
Write-Host "  ============================================================"
Write-Host "    PASO 2 - Prepara el USB o carpeta de instalacion"
Write-Host "  ============================================================"
Write-Host ""
Write-Host "  Pon estos 2 archivos juntos en un USB:"
Write-Host ""
Write-Host "    pizza_deploy_key       <- archivo privado (en tu Escritorio)"
Write-Host "    setup_completo.bat     <- esta en el repo"
Write-Host ""
Write-Host "  En cada PC nueva solo conectas el USB y doble clic en setup_completo.bat"
Write-Host ""
Write-Host "  IMPORTANTE: Guarda pizza_deploy_key en un lugar seguro."
Write-Host "  Si lo pierdes solo hay que generar uno nuevo y subirlo a GitHub."
Write-Host ""
Write-Host "  Archivos generados en tu Escritorio:"
Write-Host "    $keyPath"
Write-Host "    $keyPath.pub"
Write-Host ""
pause
