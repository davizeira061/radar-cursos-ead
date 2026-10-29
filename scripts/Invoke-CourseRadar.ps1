<#
.SYNOPSIS
    Orquestrador em PowerShell para o Radar de Cursos EAD.
.DESCRIPTION
    Executa a coleta em Python, gera relatório semanal em Markdown,
    atualiza o README do repositório, alimenta o resumo do GitHub Actions ($env:GITHUB_STEP_SUMMARY)
    e efetua commit/push automático caso executado em ambiente de CI/CD.
#>

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$SkipGitCommit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Garante saída em UTF-8 no terminal
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$RepoRoot = Resolve-Path "$PSScriptRoot\.."
$ScriptPy = Join-Path $PSScriptRoot "fetch_courses.py"
$LatestMd = Join-Path $RepoRoot "data\latest_courses.md"
$LatestJson = Join-Path $RepoRoot "data\latest_courses.json"
$ReportsDir = Join-Path $RepoRoot "reports"
$ReadmePath = Join-Path $RepoRoot "README.md"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "🚀 INICIANDO RADAR DE CURSOS GRATUITOS EAD (POWERSHELL)" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Localiza o executável do Python
$PythonCmd = $null
if (Get-Command "python3" -ErrorAction SilentlyContinue) {
    $PythonCmd = "python3"
} elseif (Get-Command "python" -ErrorAction SilentlyContinue) {
    $PythonCmd = "python"
} elseif (Get-Command "py" -ErrorAction SilentlyContinue) {
    $PythonCmd = "py"
} else {
    Write-Warning "Python não foi encontrado diretamente no PATH."
    # Tenta caminhos comuns no Windows
    $possiblePaths = @(
        "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe",
        "C:\Program Files\Python3*\python.exe",
        "C:\Python3*\python.exe"
    )
    foreach ($path in $possiblePaths) {
        $found = Get-Item $path -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            $PythonCmd = $found.FullName
            break
        }
    }
}

if (-not $PythonCmd) {
    Write-Error "Python é obrigatório para a coleta dos dados. Por favor, instale o Python ou execute no GitHub Actions."
    exit 1
}

Write-Host "[+] Interpretador Python detectado: $PythonCmd" -ForegroundColor Green

# 2. Executa o coletor Python
$pyArgs = @($ScriptPy)
if ($Force) {
    $pyArgs += "--force"
}

Write-Host "[*] Executando script coletor..." -ForegroundColor Yellow
& $PythonCmd @pyArgs

if (-not (Test-Path $LatestMd)) {
    Write-Error "O arquivo de saída $LatestMd não foi gerado pelo script Python."
    exit 1
}

$markdownContent = Get-Content -Path $LatestMd -Raw -Encoding UTF8

# 3. Alimenta o GitHub Actions Step Summary (se executado no CI)
if ($env:GITHUB_STEP_SUMMARY) {
    Write-Host "[+] Alimentando GITHUB_STEP_SUMMARY..." -ForegroundColor Green
    Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $markdownContent -Encoding UTF8
}

# 4. Cria arquivo semanal arquivado em reports/AAAA-MM-DD.md
$today = (Get-Date).ToString("yyyy-MM-dd")
$weeklyReportPath = Join-Path $ReportsDir "$today-cursos-gratuitos.md"
Set-Content -Path $weeklyReportPath -Value $markdownContent -Encoding UTF8
Write-Host "[+] Relatório arquivado em: $weeklyReportPath" -ForegroundColor Green

# 5. Atualiza o README.md incorporando os novos cursos
if (Test-Path $ReadmePath) {
    Write-Host "[*] Atualizando seção dinâmica no README.md..." -ForegroundColor Yellow
    $readmeContent = Get-Content -Path $ReadmePath -Raw -Encoding UTF8
    $startTag = "<!-- COURSES_START -->"
    $endTag = "<!-- COURSES_END -->"

    if ($readmeContent.Contains($startTag) -and $readmeContent.Contains($endTag)) {
        $pattern = "(?s)" + [regex]::Escape($startTag) + ".*?" + [regex]::Escape($endTag)
        $replacement = "$startTag`n`n$markdownContent`n`n$endTag"
        $newReadme = [regex]::Replace($readmeContent, $pattern, $replacement)
        Set-Content -Path $ReadmePath -Value $newReadme -Encoding UTF8
        Write-Host "[+] README.md atualizado com sucesso." -ForegroundColor Green
    } else {
        Write-Host "[i] Tags de marcação não encontradas no README.md. Pulando substituição inline." -ForegroundColor Gray
    }
}

# 6. Commit e Push no GitHub Actions se houver modificações
$isCi = ($env:GITHUB_ACTIONS -eq "true")

if ($isCi -and -not $SkipGitCommit) {
    Write-Host "[*] Ambiente de CI (GitHub Actions) detectado. Verificando alterações Git..." -ForegroundColor Yellow
    
    git config --global user.name "github-actions[bot]"
    git config --global user.email "github-actions[bot]@users.noreply.github.com"
    
    $status = git status --porcelain
    if ($status) {
        Write-Host "[+] Alterações detectadas no repositório. Commitando..." -ForegroundColor Green
        git add data/history.json reports/ README.md
        git commit -m "chore(radar): atualização semanal do radar de cursos gratuitos [skip ci]"
        git push
        Write-Host "[✓] Push realizado com sucesso no repositório remoto!" -ForegroundColor Green
    } else {
        Write-Host "[i] Nenhuma novidade para commitar. Repositório já está sincronizado." -ForegroundColor Cyan
    }
} else {
    Write-Host "[✓] Execução local concluída com sucesso." -ForegroundColor Green
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "🎯 Radar finalizado com êxito!" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
