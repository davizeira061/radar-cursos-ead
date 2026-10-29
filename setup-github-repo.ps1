<#
.SYNOPSIS
    Script auxiliar para inicializar e enviar o repositorio ao GitHub.
.DESCRIPTION
    Inicializa o repositorio git local, cria o primeiro commit e conecta ao repositorio remoto informado pelo usuario.
#>

[CmdletBinding()]
param(
    [string]$RemoteUrl
)

$ErrorActionPreference = "Stop"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "[*] ASSISTENTE DE PUBLICACAO DO RADAR NO GITHUB" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$CurrentDir = $PSScriptRoot
Set-Location $CurrentDir

# 1. Verifica se o git ja esta inicializado
if (-not (Test-Path ".git")) {
    Write-Host "[*] Inicializando repositorio Git local..." -ForegroundColor Yellow
    git init -b main
} else {
    Write-Host "[i] Repositorio Git ja inicializado." -ForegroundColor Green
}

# 2. Configura e adiciona arquivos
Write-Host "[*] Adicionando arquivos ao Git..." -ForegroundColor Yellow
git add .

# 3. Commit inicial se nao houver commits
$hasCommits = $false
try {
    $log = git log -1 --oneline 2>$null
    if ($log) {
        $hasCommits = $true
    }
} catch {
    $hasCommits = $false
}

if (-not $hasCommits) {
    Write-Host "[*] Criando commit inicial..." -ForegroundColor Yellow
    git commit -m "feat: setup inicial do radar de cursos ead com powershell e python"
} else {
    $diff = git status --porcelain
    if ($diff) {
        Write-Host "[*] Criando commit de alteracoes pendentes..." -ForegroundColor Yellow
        git commit -m "chore: atualizacoes do radar de cursos ead"
    } else {
        Write-Host "[i] Todos os arquivos ja estao commitados." -ForegroundColor Green
    }
}

# 4. Configuracao do Remote
$existingRemote = ""
try {
    $existingRemote = (git remote get-url origin 2>$null)
} catch {
    $existingRemote = ""
}

if (-not $existingRemote) {
    if (-not $RemoteUrl) {
        Write-Host ""
        Write-Host "Cole a URL do seu repositorio GitHub criado (ex: https://github.com/davizeira/radar-cursos-ead.git):" -ForegroundColor Magenta
        $RemoteUrl = Read-Host "URL do Repositorio Remoto"
    }

    if ($RemoteUrl) {
        git remote add origin $RemoteUrl.Trim()
        Write-Host "[+] Remote 'origin' adicionado: $RemoteUrl" -ForegroundColor Green
    } else {
        Write-Warning "Nenhum remote informado. O repositorio esta pronto localmente, mas nao foi enviado ao GitHub."
        exit 0
    }
} else {
    Write-Host "[i] Remote 'origin' ja configurado: $existingRemote" -ForegroundColor Green
}

# 5. Push para o GitHub
Write-Host ""
Write-Host "[*] Deseja realizar o push para o GitHub agora na branch 'main'? (S/N)" -ForegroundColor Yellow
$resp = Read-Host "Push agora? [S/N]"
if ($resp -match "^[sSyY]") {
    Write-Host "[*] Enviando para o GitHub..." -ForegroundColor Yellow
    git push -u origin main
    Write-Host "[OK] Repositorio publicado com sucesso!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Lembre-se de configurar a permissao de escrita no GitHub:" -ForegroundColor Cyan
    Write-Host "  Settings > Actions > General > Workflow permissions > Read and write permissions" -ForegroundColor Cyan
} else {
    Write-Host "[i] Voce pode enviar manualmente quando desejar executando:" -ForegroundColor Gray
    Write-Host "    git push -u origin main" -ForegroundColor White
}
