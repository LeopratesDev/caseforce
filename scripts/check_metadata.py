"""Verificacoes baratas dos metadados, sem precisar de org nem de segredo.

Pega os erros que so apareceriam num deploy: XML ou JSON quebrado, classe sem o
arquivo -meta.xml, versao de API fora do padrao do projeto e credencial esquecida no
codigo. Roda local (python scripts/check_metadata.py) e no CI.
"""
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "force-app"

# Padroes de credencial que nunca devem entrar no repositorio.
SECRET_PATTERNS = {
    "URL de autenticacao do sfdx": re.compile(r"force://[A-Za-z0-9._-]+:[A-Za-z0-9._-]+:"),
    "token Bearer": re.compile(r"Bearer\s+[A-Za-z0-9._-]{20,}"),
    "session id do Salesforce": re.compile(r"\b00D[A-Za-z0-9]{12,15}![A-Za-z0-9._]{20,}"),
}
TEXT_SUFFIXES = {".cls", ".trigger", ".xml", ".js", ".html", ".css", ".json", ".md", ".yml", ".yaml", ".py", ".apex"}
SKIP_DIRS = {"node_modules", ".git", "coverage", ".sfdx", ".sf"}

errors = []


def fail(message):
    errors.append(message)


def rel(path):
    return path.relative_to(ROOT).as_posix()


def source_api_version():
    project = json.loads((ROOT / "sfdx-project.json").read_text(encoding="utf-8"))
    return project["sourceApiVersion"]


def check_xml_and_api_version(expected_version):
    api_tags = (".cls-meta.xml", ".trigger-meta.xml", ".js-meta.xml", ".flow-meta.xml")
    for path in sorted(SOURCE.rglob("*.xml")):
        try:
            tree = ET.parse(path)
        except ET.ParseError as error:
            fail(f"{rel(path)}: XML invalido ({error})")
            continue
        if path.name.endswith(api_tags):
            node = tree.getroot().find("{http://soap.sforce.com/2006/04/metadata}apiVersion")
            if node is None or node.text != expected_version:
                found = "ausente" if node is None else node.text
                fail(f"{rel(path)}: apiVersion {found}, esperado {expected_version}")


def check_json():
    for path in sorted(ROOT.glob("*.json")) + sorted((ROOT / "config").glob("*.json")):
        if path.name == "package-lock.json":
            continue
        try:
            json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            fail(f"{rel(path)}: JSON invalido ({error})")


def check_meta_pairs():
    for path in sorted(SOURCE.rglob("*")):
        if path.suffix in {".cls", ".trigger"}:
            if not Path(str(path) + "-meta.xml").exists():
                fail(f"{rel(path)}: falta o arquivo {path.name}-meta.xml (o deploy falha sem ele)")
        elif path.name.endswith((".cls-meta.xml", ".trigger-meta.xml")):
            if not Path(str(path)[: -len("-meta.xml")]).exists():
                fail(f"{rel(path)}: -meta.xml sem o codigo correspondente")


def check_test_classes():
    for path in sorted((SOURCE / "main" / "default" / "classes").glob("*Test.cls")):
        if "@IsTest" not in path.read_text(encoding="utf-8"):
            fail(f"{rel(path)}: classe de teste sem @IsTest")


def check_secrets():
    for path in sorted(ROOT.rglob("*")):
        if not path.is_file() or path.suffix not in TEXT_SUFFIXES:
            continue
        if SKIP_DIRS & set(path.relative_to(ROOT).parts) or path.name == "package-lock.json":
            continue
        if path == Path(__file__).resolve():
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        for label, pattern in SECRET_PATTERNS.items():
            if pattern.search(text):
                fail(f"{rel(path)}: parece conter {label}")


def main():
    version = source_api_version()
    check_xml_and_api_version(version)
    check_json()
    check_meta_pairs()
    check_test_classes()
    check_secrets()

    if errors:
        print(f"{len(errors)} problema(s) encontrado(s):")
        for message in errors:
            print(f"  - {message}")
        return 1

    xml_count = sum(1 for _ in SOURCE.rglob("*.xml"))
    print(f"OK: {xml_count} arquivos XML, apiVersion {version}, pares -meta.xml completos, sem credenciais.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
