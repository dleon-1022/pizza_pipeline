# =============================================================
#  GRITSEE - BOOTSTRAP
#  Pega este script en PowerShell (admin) via AnyDesk.
#  Solo necesitas hacerlo UNA VEZ por PC.
# =============================================================

Set-ExecutionPolicy Bypass -Scope Process -Force

Write-Host ""
Write-Host "  ============================================================"
Write-Host "         GRITSEE - Bootstrap de instalacion"
Write-Host "  ============================================================"
Write-Host ""
Write-Host "  Necesitas el GitHub Token (pidelo a David)."
Write-Host ""

$token = Read-Host "  GitHub Token"

if (-not $token) {
    Write-Host "  ERROR: Token vacio."
    Read-Host "  Presiona Enter para salir"
    exit 1
}

$repoUrl   = "https://$token@github.com/dleon-1022/PC-configuration.git"
$cloneDir  = "C:\PC-configuration"

# ── 1. Instalar Git si no está ────────────────────────────────
Write-Host ""
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "  [1/3] Instalando Git..."
    winget install Git.Git -e --silent --accept-package-agreements --accept-source-agreements | Out-Null
    # Refrescar PATH
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" + $env:PATH
    Write-Host "        Git instalado [OK]"
} else {
    Write-Host "  [1/3] Git ya instalado [OK]"
}

# ── 2. Clonar o actualizar repo ───────────────────────────────
Write-Host ""
if (Test-Path "$cloneDir\.git") {
    Write-Host "  [2/3] Repo existente — actualizando..."
    git -C $cloneDir remote set-url origin $repoUrl
    git -C $cloneDir pull
} else {
    Write-Host "  [2/3] Clonando repositorio..."
    git clone $repoUrl $cloneDir
}

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "  ERROR: No se pudo clonar el repo."
    Write-Host "  Verifica que el token sea correcto y tenga acceso al repo."
    Read-Host "  Presiona Enter para salir"
    exit 1
}
Write-Host "        Repositorio listo [OK]"

# ── Guardar credencial para futuros git pull ──────────────────
$credsFile = "$env:USERPROFILE\.git-credentials"
$credLine  = "https://${token}:x-oauth-basic@github.com"
$existing  = if (Test-Path $credsFile) { Get-Content $credsFile } else { @() }
if ($existing -notcontains $credLine) {
    Add-Content $credsFile $credLine
}
git -C $cloneDir config credential.helper store | Out-Null

# ── 3. Correr configuracion ───────────────────────────────────
Write-Host ""
Write-Host "  [3/3] Iniciando configuracion del sistema..."
Write-Host ""
Start-Process cmd -ArgumentList "/c `"$cloneDir\configuracion.bat`"" -Verb RunAs -Wait
