"""Génère les drapeaux des pays dans assets/flags/<TAG>.svg.

Sources :
- paquet npm « flag-icons » (licence MIT), version fixée dans config.json ;
- Wikimedia Commons (domaine public) pour les drapeaux absents ou différents
  de la situation de fait au 1er janvier 2026 (section « commons » de config.json).

Tous les drapeaux sont mis au format de config.json (4:3) pour s'afficher de
façon homogène dans l'interface : recadrés au centre, ou complétés par une
couleur de fond quand le recadrage couperait une inscription.

Usage : python tools/flag_gen/generate_flags.py
"""

from __future__ import annotations

import io
import json
import re
import sys
import tarfile
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOL_DIR = Path(__file__).resolve().parent
CACHE_DIR = TOOL_DIR / "cache"
OUT_DIR = ROOT / "assets" / "flags"
COUNTRIES_PATH = ROOT / "data" / "countries" / "countries.json"
USER_AGENT = "StatecraftFlagTool/1.0 (https://github.com/Chronos8001/Statecraft)"
COMMONS_API = "https://commons.wikimedia.org/w/api.php"
NPM_REGISTRY = "https://registry.npmjs.org"

SVG_TAG = re.compile(r"<svg\b[^>]*>", re.S)
ATTRIBUTE = re.compile(r'\s(width|height|viewBox|preserveAspectRatio)\s*=\s*"[^"]*"')


def download(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def cached(name: str, url_factory) -> bytes:
    path = CACHE_DIR / name
    if not path.exists():
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        # Empêche Godot d'importer le cache comme ressource du jeu.
        (CACHE_DIR / ".gdignore").touch()
        path.write_bytes(download(url_factory()))
    return path.read_bytes()


def package_flags(package: dict) -> tuple[dict[str, str], str]:
    """SVG du paquet npm indexés par code ISO2 en minuscules, et texte de sa licence."""
    name, version = package["name"], package["version"]
    archive = cached(f"{name}-{version}.tgz", lambda: f"{NPM_REGISTRY}/{name}/-/{name}-{version}.tgz")
    prefix = f"package/{package['folder']}/"
    flags: dict[str, str] = {}
    license_text = ""
    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:gz") as tar:
        for member in tar.getmembers():
            if not member.isfile():
                continue
            if member.name.startswith(prefix) and member.name.endswith(".svg"):
                code = member.name[len(prefix):-4]
                flags[code] = tar.extractfile(member).read().decode("utf-8")
            elif member.name == "package/LICENSE":
                license_text = tar.extractfile(member).read().decode("utf-8")
    return flags, license_text


def commons_url(file_name: str) -> str:
    query = urllib.parse.urlencode({
        "action": "query", "titles": f"File:{file_name}", "prop": "imageinfo",
        "iiprop": "url", "format": "json",
    })
    pages = json.loads(download(f"{COMMONS_API}?{query}"))["query"]["pages"]
    page = next(iter(pages.values()))
    if "imageinfo" not in page:
        raise SystemExit(f"Fichier introuvable sur Wikimedia Commons : {file_name}")
    return page["imageinfo"][0]["url"].split("?")[0]


def commons_flag(file_name: str) -> str:
    return cached(f"commons_{file_name}", lambda: commons_url(file_name)).decode("utf-8")


def view_box(svg_tag: str) -> tuple[float, float, float, float]:
    match = re.search(r'viewBox\s*=\s*"([^"]+)"', svg_tag)
    if match:
        x, y, w, h = (float(v) for v in match.group(1).replace(",", " ").split())
        return x, y, w, h
    width = re.search(r'\swidth\s*=\s*"([\d.eE+-]+)', svg_tag)
    height = re.search(r'\sheight\s*=\s*"([\d.eE+-]+)', svg_tag)
    if not (width and height):
        raise ValueError("SVG sans viewBox ni dimensions")
    return 0.0, 0.0, float(width.group(1)), float(height.group(1))


def normalize(svg: str, size: tuple[int, int], background: str = "") -> str:
    """Met le drapeau au format voulu et fixe sa taille de rendu.

    Sans fond : recadrage au centre. Avec un fond : le cadre est agrandi et
    complété par cette couleur, pour ne rien couper (inscriptions près des bords).
    """
    svg = re.sub(r"<\?xml[^>]*\?>\s*", "", svg)
    svg = re.sub(r"<!DOCTYPE[^>]*>\s*", "", svg)
    tag_match = SVG_TAG.search(svg)
    if tag_match is None:
        raise ValueError("balise <svg> absente")
    tag = tag_match.group(0)
    x, y, w, h = view_box(tag)
    ratio = size[0] / size[1]
    too_wide = w / h > ratio
    if too_wide == (not background):
        new_w = h * ratio
        x += (w - new_w) / 2.0
        w = new_w
    else:
        new_h = w / ratio
        y += (h - new_h) / 2.0
        h = new_h
    new_tag = ATTRIBUTE.sub("", tag)
    box = " ".join(f"{v:g}" for v in (x, y, w, h))
    new_tag = new_tag.replace(
        "<svg", f'<svg width="{size[0]}" height="{size[1]}" viewBox="{box}" preserveAspectRatio="none"', 1)
    if background:
        new_tag += f'<rect x="{x:g}" y="{y:g}" width="{w:g}" height="{h:g}" fill="{background}"/>'
    svg = svg[:tag_match.start()] + new_tag + svg[tag_match.end():]
    return svg.replace("\r\n", "\n").strip() + "\n"


def main() -> None:
    config = json.loads((TOOL_DIR / "config.json").read_text(encoding="utf-8"))
    tags = sorted(json.loads(COUNTRIES_PATH.read_text(encoding="utf-8")).keys())
    size = (int(config["size"][0]), int(config["size"][1]))
    flags, license_text = package_flags(config["package"])

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    missing: list[str] = []
    for tag in tags:
        background = ""
        if tag in config["commons"]:
            entry = config["commons"][tag]
            source = commons_flag(entry["file"])
            background = entry.get("background", "")
        elif config["iso2"].get(tag) in flags:
            source = flags[config["iso2"][tag]]
        else:
            missing.append(tag)
            continue
        (OUT_DIR / f"{tag}.svg").write_text(normalize(source, size, background), encoding="utf-8", newline="\n")

    # La licence MIT de flag-icons accompagne les drapeaux qui en sont tirés.
    license_path = OUT_DIR / f"LICENSE-{config['package']['name']}.txt"
    license_path.write_text(license_text.replace("\r\n", "\n"), encoding="utf-8", newline="\n")

    stale = sorted(p.stem for p in OUT_DIR.glob("*.svg") if p.stem not in tags)
    for tag in stale:
        (OUT_DIR / f"{tag}.svg").unlink()
        import_file = OUT_DIR / f"{tag}.svg.import"
        if import_file.exists():
            import_file.unlink()

    print(f"{len(tags) - len(missing)} drapeaux écrits dans {OUT_DIR.relative_to(ROOT)}")
    if stale:
        print("Supprimés (pays inconnus) : " + ", ".join(stale))
    if missing:
        print("Sans source : " + ", ".join(missing), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
