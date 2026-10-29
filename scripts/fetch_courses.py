#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Radar de Cursos Gratuitos EAD
Coletor de cursos com certificação e cupons 100% OFF nos 5 pilares:
1. Infraestrutura, Redes & Segurança
2. Desenvolvimento & DevOps (Python, PowerShell, Git, CI/CD)
3. Backend com PHP & Bancos Relacionais
4. Governança de TI & Estudos para Concursos
5. Mecânica & Diagnóstico Automotivo
"""

import os
import sys
import json
import re
import urllib.request
import urllib.parse
from datetime import datetime, timezone
import xml.etree.ElementTree as ET

# Caminhos base
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG_FILE = os.path.join(BASE_DIR, "config", "keywords.json")
HISTORY_FILE = os.path.join(BASE_DIR, "data", "history.json")
OUTPUT_JSON = os.path.join(BASE_DIR, "data", "latest_courses.json")
OUTPUT_MD = os.path.join(BASE_DIR, "data", "latest_courses.md")

USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) CourseRadar/1.0"


def load_config():
    """Carrega o arquivo de configuração de palavras-chave."""
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, "r", encoding="utf-8") as f:
            return json.load(f).get("categories", {})
    return {}


def load_history():
    """Carrega o histórico de URLs já coletadas."""
    if os.path.exists(HISTORY_FILE):
        try:
            with open(HISTORY_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                return set(data.get("seen_urls", []))
        except Exception:
            return set()
    return set()


def save_history(seen_urls):
    """Salva o histórico atualizado mantendo até os últimos 1000 registros."""
    urls_list = list(seen_urls)[-1000:]
    with open(HISTORY_FILE, "w", encoding="utf-8") as f:
        json.dump({
            "updated_at": datetime.now(timezone.utc).isoformat(),
            "seen_urls": urls_list
        }, f, indent=2, ensure_ascii=False)


def fetch_url(url, timeout=15):
    """Realiza requisição HTTP simples com headers apropriados."""
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.read().decode("utf-8", errors="replace")
    except Exception as e:
        print(f"[!] Erro ao acessar {url}: {e}", file=sys.stderr)
        return None


def match_category(title, summary, categories):
    """Identifica se o curso corresponde a algum dos pilares definidos."""
    text_to_search = f"{title} {summary}".lower()
    matched_categories = []

    for cat_id, cat_data in categories.items():
        keywords = cat_data.get("keywords", [])
        for kw in keywords:
            # Busca por palavra ou termo exato
            pattern = r'\b' + re.escape(kw.lower()) + r'\b'
            if re.search(pattern, text_to_search, re.IGNORECASE):
                matched_categories.append((cat_id, cat_data.get("name"), cat_data.get("icon", "📚")))
                break

    return matched_categories


def fetch_discudemy(categories, seen_urls):
    """Coleta cupons 100% OFF da Udemy via feed do Discudemy."""
    courses = []
    feed_url = "https://www.discudemy.com/feed"
    print(f"[*] Consultando cupons Udemy no Discudemy: {feed_url}")
    xml_data = fetch_url(feed_url)
    if not xml_data:
        return courses

    try:
        root = ET.fromstring(xml_data)
        items = root.findall(".//item")
        for item in items:
            title_elem = item.find("title")
            link_elem = item.find("link")
            desc_elem = item.find("description")
            pub_elem = item.find("pubDate")

            title = title_elem.text.strip() if title_elem is not None and title_elem.text else ""
            link = link_elem.text.strip() if link_elem is not None and link_elem.text else ""
            summary = desc_elem.text.strip() if desc_elem is not None and desc_elem.text else ""
            pub_date = pub_elem.text.strip() if pub_elem is not None and pub_elem.text else ""

            # Remove tags HTML do summary
            summary_clean = re.sub(r'<[^>]+>', '', summary)

            if not link or link in seen_urls:
                continue

            matches = match_category(title, summary_clean, categories)
            if matches:
                # Limpa título
                clean_title = re.sub(r'\[100%\s*OFF\]', '', title, flags=re.IGNORECASE).strip()
                for cat_id, cat_name, cat_icon in matches:
                    courses.append({
                        "title": clean_title,
                        "url": link,
                        "source": "Udemy (Cupom 100% Grátis)",
                        "category_id": cat_id,
                        "category_name": cat_name,
                        "category_icon": cat_icon,
                        "summary": summary_clean[:220] + "..." if len(summary_clean) > 220 else summary_clean,
                        "badge": "100% OFF",
                        "published_at": pub_date
                    })
    except Exception as e:
        print(f"[!] Erro ao parsear XML do Discudemy: {e}", file=sys.stderr)

    return courses


def fetch_microsoft_learn(categories, seen_urls):
    """Consulta módulos e trilhas oficiais gratuitas no Microsoft Learn."""
    courses = []
    api_url = "https://learn.microsoft.com/api/catalog/?locale=pt-br"
    print(f"[*] Consultando API oficial do Microsoft Learn (pt-br)...")
    json_data = fetch_url(api_url, timeout=25)
    if not json_data:
        return courses

    try:
        data = json.loads(json_data)
        modules = data.get("modules", [])

        # Amostra ou módulos prioritários alinhados com TI, Redes, AD, Dev e Segurança
        for mod in modules:
            title = mod.get("title", "")
            summary = mod.get("summary", "")
            url = mod.get("url", "")
            duration = mod.get("duration_in_minutes", 0)
            levels = mod.get("levels", [])

            if not url or url in seen_urls:
                continue

            matches = match_category(title, summary, categories)
            if matches:
                level_str = levels[0].capitalize() if levels else "Geral"
                for cat_id, cat_name, cat_icon in matches:
                    courses.append({
                        "title": title,
                        "url": url,
                        "source": "Microsoft Learn (Oficial Gratuito)",
                        "category_id": cat_id,
                        "category_name": cat_name,
                        "category_icon": cat_icon,
                        "summary": summary[:220] + "..." if len(summary) > 220 else summary,
                        "badge": f"{duration} min | Nível {level_str}",
                        "published_at": "Disponível Contínuo"
                    })
                    # Limita a alguns cursos relevantes por execução para não saturar
                    if len(courses) >= 15:
                        return courses
    except Exception as e:
        print(f"[!] Erro ao processar Microsoft Learn API: {e}", file=sys.stderr)

    return courses


def fetch_evg_enap(categories, seen_urls):
    """Coleta cursos com certificado do catálogo da Escola Virtual de Governo (EV.G / ENAP)."""
    courses = []
    catalog_url = "https://www.escolavirtual.gov.br/catalogo"
    print(f"[*] Consultando catálogo da Escola Virtual de Governo (EV.G)...")
    html = fetch_url(catalog_url, timeout=15)
    if not html:
        return courses

    try:
        # Extrai links de cursos: https://www.escolavirtual.gov.br/curso/{id}
        pattern = r'<h3 class="card-title"><a href="(https://www.escolavirtual.gov.br/curso/\d+)">([^<]+)</a></h3>'
        matches_found = re.findall(pattern, html)

        for link, title in matches_found:
            title = title.strip()
            if not link or link in seen_urls:
                continue

            matches = match_category(title, "", categories)
            if matches:
                for cat_id, cat_name, cat_icon in matches:
                    courses.append({
                        "title": title,
                        "url": link,
                        "source": "Escola Virtual Gov (EV.G / ENAP)",
                        "category_id": cat_id,
                        "category_name": cat_name,
                        "category_icon": cat_icon,
                        "summary": "Curso gratuito oficial com emissão de certificado Gov.br e ENAP.",
                        "badge": "Certificado Grátis Gov.br",
                        "published_at": "Inscrições Abertas"
                    })
    except Exception as e:
        print(f"[!] Erro ao processar catálogo EV.G: {e}", file=sys.stderr)

    return courses


def get_curated_reference_courses(categories, seen_urls):
    """Cursos perenes de altíssimo valor (Cisco NetAcad, IFRS MOOC, Bradesco) com certificação."""
    curated = [
        # Cisco Skills for All / NetAcad
        {
            "title": "Cisco Networking Basics & Redes de Computadores",
            "url": "https://skillsforall.com/course/networking-basics",
            "source": "Cisco Skills For All",
            "summary": "Fundamentos essenciais de redes, arquitetura TCP/IP, roteadores, switches e endereçamento IP.",
            "badge": "Certificado Oficial Cisco"
        },
        {
            "title": "Cisco Cybersecurity Essentials",
            "url": "https://skillsforall.com/course/cybersecurity-essentials",
            "source": "Cisco Skills For All",
            "summary": "Conceitos fundamentais de segurança, táticas de defesa, ameaças cibernéticas e boas práticas corporativas.",
            "badge": "Certificado Oficial Cisco"
        },
        {
            "title": "Python Essentials 1 (Cisco / Python Institute)",
            "url": "https://skillsforall.com/course/python-essentials-1",
            "source": "Cisco Skills For All",
            "summary": "Preparatório oficial OpenEDG para a certificação PCEP (Certified Entry-Level Python Programmer).",
            "badge": "Certificado Oficial Cisco"
        },
        # IFRS MOOC (Instituto Federal RS) - Notável em Automotiva e TI
        {
            "title": "Eletricidade Básica Automotiva e Circuitos",
            "url": "https://mooc.ifrs.edu.br/course/index.php?categoryid=11",
            "source": "IFRS MOOC (Instituto Federal)",
            "summary": "Conceitos de grandezas elétricas, circuitos, fusíveis, relés e leitura de esquemas automotivos.",
            "badge": "Certificado Gratuito MEC"
        },
        {
            "title": "Administração de Redes de Computadores & Servidores",
            "url": "https://mooc.ifrs.edu.br/course/index.php?categoryid=3",
            "source": "IFRS MOOC (Instituto Federal)",
            "summary": "Configuração de serviços de rede, topologias, protocolos e administração de ambientes de TI.",
            "badge": "Certificado Gratuito MEC"
        },
        # Fundação Bradesco
        {
            "title": "Segurança em Tecnologia da Informação",
            "url": "https://www.ev.org.br/cursos/seguranca-em-tecnologia-da-informacao",
            "source": "Fundação Bradesco - Escola Virtual",
            "summary": "Fundamentos de segurança de redes, políticas de acesso, criptografia e proteção de infraestruturas.",
            "badge": "Certificado Fundação Bradesco"
        },
        {
            "title": "Modelagem de Dados e Bancos Relacionais SQL",
            "url": "https://www.ev.org.br/cursos/modelagem-de-dados",
            "source": "Fundação Bradesco - Escola Virtual",
            "summary": "Diagrama de entidade-relacionamento (DER), normalização, chaves e fundamentos de SQL.",
            "badge": "Certificado Fundação Bradesco"
        }
    ]

    courses = []
    for c in curated:
        if c["url"] in seen_urls:
            continue
        matches = match_category(c["title"], c["summary"], categories)
        if matches:
            for cat_id, cat_name, cat_icon in matches:
                courses.append({
                    "title": c["title"],
                    "url": c["url"],
                    "source": c["source"],
                    "category_id": cat_id,
                    "category_name": cat_name,
                    "category_icon": cat_icon,
                    "summary": c["summary"],
                    "badge": c["badge"],
                    "published_at": "Disponível Contínuo"
                })

    return courses


def generate_markdown(courses, categories):
    """Gera o relatório estruturado em Markdown."""
    now_str = datetime.now().strftime("%d/%m/%Y às %H:%M")
    md_lines = [
        f"## 🎯 Radar Semanal de Cursos Gratuitos EAD",
        f"> **Atualizado em:** {now_str} | **Total de Oportunidades Encontradas:** {len(courses)}",
        "",
        "Lista automatizada semanalmente via **GitHub Actions** cruzando APIs oficiais, feeds de cupons 100% OFF e instituições públicas de ensino.",
        ""
    ]

    # Agrupa por categoria
    grouped = {}
    for cat_id in categories.keys():
        grouped[cat_id] = []

    for c in courses:
        cat_id = c.get("category_id")
        if cat_id in grouped:
            grouped[cat_id].append(c)

    # Itera sobre categorias
    for cat_id, cat_data in categories.items():
        cat_name = cat_data.get("name")
        cat_icon = cat_data.get("icon", "📚")
        cat_courses = grouped.get(cat_id, [])

        md_lines.append(f"### {cat_icon} {cat_name} ({len(cat_courses)})")
        if not cat_courses:
            md_lines.append("_Nenhum novo curso detectado nesta categoria nesta rodada._\n")
            continue

        md_lines.append("| Curso | Plataforma / Fonte | Destaque | Link Direto |")
        md_lines.append("| :--- | :--- | :---: | :---: |")

        for c in cat_courses:
            title = c['title'].replace("|", "-")
            source = c['source'].replace("|", "-")
            badge = c['badge'].replace("|", "-")
            url = c['url']
            summary = c.get('summary', '').replace("|", "-").replace("\n", " ")

            md_lines.append(f"| **{title}**<br><small>{summary}</small> | `{source}` | `{badge}` | [Acessar Curso 🚀]({url}) |")

        md_lines.append("")

    return "\n".join(md_lines)


def main():
    force_all = "--force" in sys.argv
    print("==================================================")
    print("🛰️  RADAR DE CURSOS GRATUITOS EAD - DAVI (ANTIGRAVITY)")
    print("==================================================")

    categories = load_config()
    seen_urls = set() if force_all else load_history()
    print(f"[*] Histórico carregado: {len(seen_urls)} URLs já monitoradas.")

    all_courses = []

    # 1. Discudemy (Udemy 100% OFF)
    discudemy_courses = fetch_discudemy(categories, seen_urls)
    print(f"[+] Discudemy: {len(discudemy_courses)} cursos encontrados.")
    all_courses.extend(discudemy_courses)

    # 2. Microsoft Learn (Oficial)
    ms_courses = fetch_microsoft_learn(categories, seen_urls)
    print(f"[+] Microsoft Learn: {len(ms_courses)} módulos encontrados.")
    all_courses.extend(ms_courses)

    # 3. EV.G (Escola Virtual Gov / ENAP)
    evg_courses = fetch_evg_enap(categories, seen_urls)
    print(f"[+] EV.G (Gov.br): {len(evg_courses)} cursos encontrados.")
    all_courses.extend(evg_courses)

    # 4. Cursos de Referência (Cisco, IFRS MOOC, Bradesco)
    ref_courses = get_curated_reference_courses(categories, seen_urls)
    print(f"[+] Cursos de Referência/Certificação: {len(ref_courses)} cursos.")
    all_courses.extend(ref_courses)

    # Deduplicação interna por URL
    unique_courses = []
    seen_in_run = set()
    for c in all_courses:
        if c["url"] not in seen_in_run:
            seen_in_run.add(c["url"])
            unique_courses.append(c)
            seen_urls.add(c["url"])

    print(f"\n[✓] Total consolidado único: {len(unique_courses)} cursos.")

    # Salva JSON
    with open(OUTPUT_JSON, "w", encoding="utf-8") as f:
        json.dump(unique_courses, f, indent=2, ensure_ascii=False)
    print(f"[✓] Dados salvos em: {OUTPUT_JSON}")

    # Salva Markdown
    md_content = generate_markdown(unique_courses, categories)
    with open(OUTPUT_MD, "w", encoding="utf-8") as f:
        f.write(md_content)
    print(f"[✓] Markdown gerado em: {OUTPUT_MD}")

    # Atualiza histórico
    save_history(seen_urls)
    print(f"[✓] Histórico atualizado com sucesso ({len(seen_urls)} URLs registradas).")


if __name__ == "__main__":
    main()
