"""Synthetic tables only: no game assets or UnityPy installation required."""
import importlib.util
import tempfile
import unittest
import weakref
from pathlib import Path
from types import SimpleNamespace

spec = importlib.util.spec_from_file_location("extractor", Path(__file__).parents[1] / "src" / "extract_languages.py")
extractor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(extractor)


class Reader:
    type = SimpleNamespace(name="MonoBehaviour")

    def __init__(self, environment, tree):
        self.environment = weakref.ref(environment)
        self.tree = tree

    def read_typetree(self):
        # UnityPy's custom MonoBehaviour parsing depends on its environment.
        if self.environment() is None:
            raise RuntimeError("Asset environment was released too early")
        return self.tree


class Environment:
    def __init__(self, tree):
        self.objects = [Reader(self, tree)]


class Loader:
    @staticmethod
    def load(data):
        name = data.decode('utf-8')
        if "shared" in name:
            tree = {"m_TableCollectionName": "Synthetic", "m_Entries": [{"m_Id": 1, "m_Key": "greeting"}, {"m_Id": 2, "m_Key": "fallback"}]}
        elif "english" in name:
            tree = {"m_Name": "Synthetic_en", "m_TableData": [{"m_Id": 1, "m_Localized": "Sample hello"}, {"m_Id": 2, "m_Localized": "Sample fallback"}]}
        else:
            tree = {"m_Name": "Synthetic_zh", "m_TableData": [{"m_Id": 1, "m_Localized": "Sample Chinese"}]}
        return Environment(tree)


class ExtractorTests(unittest.TestCase):
    def test_environment_lifetime_and_missing_chinese_fallback(self):
        with tempfile.TemporaryDirectory() as temporary:
            bundles = Path(temporary)
            for name in ("localization-assets-shared_assets_all.bundle", "english(en).bundle", "chinese(simplified)(zh).bundle"):
                (bundles / name).write_text(name, encoding='utf-8')
            rows, summary = extractor.extract(bundles, Loader)
            self.assertEqual(rows, [["Synthetic", "greeting", "Sample hello", "Sample Chinese"], ["Synthetic", "fallback", "Sample fallback", "Sample fallback"]])
            self.assertEqual(summary, {"tables": 1, "entries": 2, "missingChinese": 1})

    def test_missing_bundles_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaisesRegex(ValueError, "Shared localization bundle missing"):
                extractor.extract(Path(temporary), Loader)


if __name__ == "__main__":
    unittest.main()
