"""Read EN/ZH tables from the user's own installed game. Never upload the output."""
import argparse
import json
import os
import sys
from pathlib import Path


def local_path(path):
    absolute = str(path.resolve())
    if os.name == "nt" and not absolute.startswith("\\\\?\\"):
        absolute = "\\\\?\\UNC\\" + absolute[2:] if absolute.startswith("\\\\") else "\\\\?\\" + absolute
    return Path(absolute)


def extract(bundles, unitypy):
    shared = {}
    shared_bundles = sorted(bundles.glob("localization-assets-shared_assets*.bundle"))
    if not shared_bundles:
        raise ValueError("Shared localization bundle missing; this game build is unsupported.")
    for bundle in shared_bundles:
        # Read bytes directly: UnityPy/fsspec path normalization can lose the
        # Windows extended-path prefix in deep Steam library directories.
        environment = unitypy.load(bundle.read_bytes())
        for obj in environment.objects:
            if obj.type.name != "MonoBehaviour":
                continue
            tree = obj.read_typetree()
            if "m_TableCollectionName" in tree:
                shared[tree["m_TableCollectionName"]] = {
                    e["m_Id"]: e["m_Key"] for e in tree["m_Entries"]
                }
    languages = {}
    for language, pattern in (("en", "*english(en)*"), ("zh", "*chinese(simplified)(zh)*")):
        languages[language] = {}
        language_bundles = sorted(bundles.glob(pattern))
        if not language_bundles:
            raise ValueError(f"{language} localization bundles missing.")
        for bundle in language_bundles:
            environment = unitypy.load(bundle.read_bytes())
            for obj in environment.objects:
                if obj.type.name != "MonoBehaviour":
                    continue
                tree = obj.read_typetree()
                name = tree.get("m_Name", "").rsplit("_", 1)[0]
                if "m_TableData" in tree:
                    languages[language][name] = {
                        e["m_Id"]: e["m_Localized"] for e in tree["m_TableData"]
                    }
    rows, missing = [], 0
    for name, entries in languages["en"].items():
        translated = languages["zh"].get(name, {})
        for identifier, english in entries.items():
            chinese = translated.get(identifier) or english
            missing += int(chinese == english and identifier not in translated)
            rows.append([name, shared.get(name, {}).get(identifier, str(identifier)), english, chinese])
    if not rows or not any(row[2] != row[3] for row in rows):
        raise ValueError("No usable bilingual pairs found; installation has been stopped.")
    return rows, {"tables": len(languages["en"]), "entries": len(rows), "missingChinese": missing}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--pydeps", type=Path)
    args = parser.parse_args()
    if args.pydeps:
        sys.path.insert(0, str(args.pydeps.resolve()))
    import UnityPy
    bundles = local_path(args.game) / "Probably Stolen_Data" / "StreamingAssets" / "aa" / "StandaloneWindows64"
    rows, summary = extract(bundles, UnityPy)
    destination = local_path(args.output)
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(rows, ensure_ascii=False), encoding="utf-8")
    temporary.replace(destination)
    summary["bytes"] = destination.stat().st_size
    print(json.dumps(summary))


if __name__ == "__main__":
    main()
