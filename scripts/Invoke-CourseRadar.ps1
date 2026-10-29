<#
.SYNOPSIS
    Orquestrador em PowerShell para o Radar de Cursos EAD.
.DESCRIPTION
    Executa a coleta em Python (ou modo nativo em PowerShell se Python nao estiver no PATH local),
    gera relatorio semanal em Markdown, atualiza o README do repositorio, alimenta o resumo do
    GitHub Actions ($env:GITHUB_STEP_SUMMARY) e efetua commit/push automatico em CI/CD.
#>

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$SkipGitCommit
)

$ErrorActionPreference = "Stop"

# Garante codificacao correta
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$RepoRoot = Resolve-Path "$PSScriptRoot\.."
$ScriptPy = Join-Path $PSScriptRoot "fetch_courses.py"
$LatestMd = Join-Path $RepoRoot "data\latest_courses.md"
$LatestJson = Join-Path $RepoRoot "data\latest_courses.json"
$ConfigPath = Join-Path $RepoRoot "config\keywords.json"
$HistoryPath = Join-Path $RepoRoot "data\history.json"
$ReportsDir = Join-Path $RepoRoot "reports"
$ReadmePath = Join-Path $RepoRoot "README.md"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "[*] INICIANDO RADAR DE CURSOS GRATUITOS EAD" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

function Test-PythonCmd($cmd) {
    try {
        $proc = Start-Process -FilePath $cmd -ArgumentList "--version" -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\py_out.txt" -RedirectStandardError "$env:TEMP\py_err.txt"
        $proc.WaitForExit(3000) | Out-Null
        if ($proc.ExitCode -eq 0) {
            $ver = Get-Content "$env:TEMP\py_out.txt" -ErrorAction SilentlyContinue
            if (-not $ver) {
                $ver = Get-Content "$env:TEMP\py_err.txt" -ErrorAction SilentlyContinue
            }
            if ($ver -match "Python\s+\d+") {
                return $true
            }
        }
    } catch {
        return $false
    }
    return $false
}

# 1. Localiza interpretador Python funcional
$PythonCmd = $null
$candidates = @("python3", "python", "py")
foreach ($c in $candidates) {
    if (Get-Command $c -ErrorAction SilentlyContinue) {
        if (Test-PythonCmd $c) {
            $PythonCmd = $c
            break
        }
    }
}

if (-not $PythonCmd) {
    # Tenta caminhos comuns no Windows
    $possiblePaths = @(
        "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe",
        "C:\Program Files\Python3*\python.exe",
        "C:\Python3*\python.exe"
    )
    foreach ($p in $possiblePaths) {
        $found = Get-Item $p -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found -and (Test-PythonCmd $found.FullName)) {
            $PythonCmd = $found.FullName
            break
        }
    }
}

# 2. Executa a Coleta (Python ou Fallback Nativo PowerShell)
if ($PythonCmd) {
    Write-Host "[+] Interpretador Python detectado: $PythonCmd" -ForegroundColor Green
    $pyArgs = @($ScriptPy)
    if ($Force) {
        $pyArgs += "--force"
    }
    Write-Host "[*] Executando coletor Python (fetch_courses.py)..." -ForegroundColor Yellow
    & $PythonCmd @pyArgs
} else {
    Write-Host "[i] Python funcional nao detectado localmente no PATH." -ForegroundColor Yellow
    Write-Host "[*] Executando rotina nativa em PowerShell para coleta..." -ForegroundColor Cyan

    $config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $seenUrls = @()
    if (-not $Force -and (Test-Path $HistoryPath)) {
        try {
            $hist = Get-Content $HistoryPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $seenUrls = $hist.seen_urls
        } catch {}
    }

    $allCourses = [System.Collections.Generic.List[PSObject]]::new()

    # Consulta Microsoft Learn API
    try {
        Write-Host "[*] Consultando Microsoft Learn API (pt-br)..." -ForegroundColor Yellow
        $msUrl = "https://learn.microsoft.com/api/catalog/?locale=pt-br"
        $msData = Invoke-RestMethod -Uri $msUrl -TimeoutSec 20 -UserAgent "CourseRadar/1.0"
        
        $categories = $config.categories.PSObject.Properties
        foreach ($mod in ($msData.modules | Select-Object -First 250)) {
            $text = "$($mod.title) $($mod.summary)".ToLower()
            foreach ($cat in $categories) {
                $matched = $false
                foreach ($kw in $cat.Value.keywords) {
                    if ($text.Contains($kw.ToLower())) {
                        $matched = $true
                        break
                    }
                }
                if ($matched -and ($seenUrls -notcontains $mod.url)) {
                    $level = "Geral"
                    $modLevels = @($mod.levels)
                    if ($modLevels.Length -gt 0) { $level = $modLevels[0] }
                    $allCourses.Add([PSCustomObject]@{
                        title = $mod.title
                        url = $mod.url
                        source = "Microsoft Learn (Oficial Gratuito)"
                        category_id = $cat.Name
                        category_name = $cat.Value.name
                        category_icon = $cat.Value.icon
                        summary = if ($mod.summary.Length -gt 220) { $mod.summary.Substring(0, 220) + "..." } else { $mod.summary }
                        badge = "$($mod.duration_in_minutes) min | $level"
                    })
                    break
                }
            }
            if ($allCourses.Count -ge 12) { break }
        }
    } catch {
        Write-Warning "Nao foi possivel consultar Microsoft Learn via PowerShell: $_"
    }

    # Cursos de Referencia
    $curated = @(
        @{
            title = "Cisco Networking Basics & Redes de Computadores"
            url = "https://skillsforall.com/course/networking-basics"
            source = "Cisco Skills For All"
            category_id = "infra_redes_seguranca"
            category_name = "Infraestrutura, Redes & Seguranca"
            category_icon = "[Redes]"
            summary = "Fundamentos essenciais de redes, arquitetura TCP/IP, roteadores, switches e enderecamento IP."
            badge = "Certificado Oficial Cisco"
        },
        @{
            title = "Cisco Cybersecurity Essentials"
            url = "https://skillsforall.com/course/cybersecurity-essentials"
            source = "Cisco Skills For All"
            category_id = "infra_redes_seguranca"
            category_name = "Infraestrutura, Redes & Seguranca"
            category_icon = "[Seguranca]"
            summary = "Conceitos fundamentais de seguranca, taticas de defesa, ameacas ciberneticas e boas praticas."
            badge = "Certificado Oficial Cisco"
        },
        @{
            title = "Python Essentials 1 (Cisco / Python Institute)"
            url = "https://skillsforall.com/course/python-essentials-1"
            source = "Cisco Skills For All"
            category_id = "dev_devops"
            category_name = "Desenvolvimento & DevOps"
            category_icon = "[Dev]"
            summary = "Preparatorio oficial OpenEDG para a certificacao PCEP (Certified Entry-Level Python Programmer)."
            badge = "Certificado Oficial Cisco"
        },
        @{
            title = "Eletricidade Basica Automotiva e Circuitos"
            url = "https://mooc.ifrs.edu.br/course/index.php?categoryid=11"
            source = "IFRS MOOC (Instituto Federal)"
            category_id = "mecanica_diagnostico"
            category_name = "Mecanica & Diagnostico Automotivo"
            category_icon = "[Auto]"
            summary = "Conceitos de grandezas eletricas, circuitos, fusiveis, reles e leitura de esquemas eletricos."
            badge = "Certificado Gratuito MEC"
        },
        @{
            title = "Modelagem de Dados e Bancos Relacionais SQL"
            url = "https://www.ev.org.br/cursos/modelagem-de-dados"
            source = "Fundacao Bradesco - Escola Virtual"
            category_id = "backend_php"
            category_name = "Desenvolvimento Backend com PHP"
            category_icon = "[PHP/SQL]"
            summary = "Diagrama de entidade-relacionamento (DER), normalizacao, chaves e fundamentos de SQL."
            badge = "Certificado Fundacao Bradesco"
        }
    )

    foreach ($c in $curated) {
        if ($seenUrls -notcontains $c.url) {
            $allCourses.Add([PSCustomObject]$c)
        }
    }

    # Salva JSON
    $jsonOut = $allCourses | ConvertTo-Json -Depth 4
    Set-Content -Path $LatestJson -Value $jsonOut -Encoding UTF8

    # Gera Markdown
    $nowStr = (Get-Date).ToString("dd/MM/yyyy as HH:mm")
    $md = @()
    $md += "## Radar Semanal de Cursos Gratuitos EAD"
    $md += "> **Atualizado em:** $nowStr | **Total de Oportunidades Encontradas:** $($allCourses.Count)"
    $md += ""
    $md += "Lista automatizada semanalmente via **GitHub Actions** cruzando APIs oficiais, feeds de cupons 100% OFF e instituicoes publicas de ensino."
    $md += ""

    $categories = $config.categories.PSObject.Properties
    foreach ($cat in $categories) {
        $catCourses = @($allCourses | Where-Object { $_.category_id -eq $cat.Name })
        $md += "### $($cat.Value.icon) $($cat.Value.name) ($($catCourses.Length))"
        if ($catCourses.Length -eq 0) {
            $md += "_Nenhum novo curso detectado nesta categoria nesta rodada._`n"
            continue
        }

        $md += "| Curso | Plataforma / Fonte | Destaque | Link Direto |"
        $md += "| :--- | :--- | :---: | :---: |"
        foreach ($c in $catCourses) {
            $cleanTitle = $c.title.Replace("|", "-")
            $cleanSource = $c.source.Replace("|", "-")
            $cleanBadge = $c.badge.Replace("|", "-")
            $cleanSummary = $c.summary.Replace("|", "-").Replace("`n", " ")
            $md += "| **$cleanTitle**<br><small>$cleanSummary</small> | ``$cleanSource`` | ``$cleanBadge`` | [Acessar Curso]($($c.url)) |"
        }
        $md += ""
    }

    $mdContent = $md -join "`n"
    Set-Content -Path $LatestMd -Value $mdContent -Encoding UTF8

    # Atualiza History
    $newUrls = @($seenUrls)
    foreach ($c in $allCourses) {
        if ($newUrls -notcontains $c.url) {
            $newUrls += $c.url
        }
    }
    $histObj = @{
        updated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        seen_urls = $newUrls | Select-Object -Last 1000
    }
    Set-Content -Path $HistoryPath -Value ($histObj | ConvertTo-Json -Depth 3) -Encoding UTF8
    Write-Host "[+] Coleta nativa concluida. $($allCourses.Count) cursos identificados." -ForegroundColor Green
}

if (-not (Test-Path $LatestMd)) {
    Write-Error "O arquivo de saida $LatestMd nao foi gerado."
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
Write-Host "[+] Relatorio arquivado em: $weeklyReportPath" -ForegroundColor Green

# 5. Atualiza o README.md incorporando os novos cursos
if (Test-Path $ReadmePath) {
    Write-Host "[*] Atualizando secao dinamica no README.md..." -ForegroundColor Yellow
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
        Write-Host "[i] Tags de marcacao nao encontradas no README.md. Pulando substituicao inline." -ForegroundColor Gray
    }
}

# 6. Commit e Push no GitHub Actions se houver modificacoes
$isCi = ($env:GITHUB_ACTIONS -eq "true")

if ($isCi -and -not $SkipGitCommit) {
    Write-Host "[*] Ambiente de CI (GitHub Actions) detectado. Verificando alteracoes Git..." -ForegroundColor Yellow
    
    git config --global user.name "github-actions[bot]"
    git config --global user.email "github-actions[bot]@users.noreply.github.com"
    
    $status = git status --porcelain
    if ($status) {
        Write-Host "[+] Alteracoes detectadas no repositorio. Commitando..." -ForegroundColor Green
        git add data/history.json reports/ README.md
        git commit -m "chore(radar): atualizacao semanal do radar de cursos gratuitos [skip ci]"
        git push
        Write-Host "[OK] Push realizado com sucesso no repositorio remoto!" -ForegroundColor Green
    } else {
        Write-Host "[i] Nenhuma novidade para commitar. Repositorio ja esta sincronizado." -ForegroundColor Cyan
    }
} else {
    Write-Host "[OK] Execucao local concluida com sucesso." -ForegroundColor Green
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "[*] Radar finalizado com exito!" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
