"""Input-isolation checks for the local terrain launcher; no client is opened."""

import hashlib
import tempfile
import unittest
from pathlib import Path

from bake_terrain import check_client, verify_files


class TerrainInputs(unittest.TestCase):
    def test_pins_reject_changed_and_missing_tool(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            file = root / "tool.py"
            file.write_bytes(b"original")
            hashes = {file.name: hashlib.sha256(file.read_bytes()).hexdigest()}
            verify_files(root, hashes)
            file.write_bytes(b"modified")
            with self.assertRaises(ValueError):
                verify_files(root, hashes)
            file.unlink()
            with self.assertRaises(ValueError):
                verify_files(root, hashes)

    def test_output_rejects_game_subdirectory_ancestor_and_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            wow = root / "game"
            wow.mkdir()
            link = root / "alias"
            link.symlink_to(wow, target_is_directory=True)
            for output in (wow, wow / "output", root, link / "output"):
                with self.subTest(output=output), self.assertRaises(ValueError):
                    check_client(wow, output, {})

    def test_product_build_must_be_unique_and_exact(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            wow = root / "game"
            wow.mkdir()
            file = wow / ".build.info"
            header = "Product!STRING:0|Active!DEC:1|Version!STRING:0\n"
            recipe = {"clientProduct": "wowf", "clientBuild": "1.60.1.70862"}
            good = "wowf|1|1.60.1.70862\n"
            file.write_text(header + "wow|1|12.1\n" + good)
            check_client(wow, root / "out", recipe)
            for rows in ("wow|1|1.60.1.70862\n", "wowf|1|1.60.1.70863\n", good + good):
                file.write_text(header + rows)
                with self.subTest(rows=rows), self.assertRaises(ValueError):
                    check_client(wow, root / "out", recipe)
            for malformed in ("", "Product|Active\nwowf|1\n", header + "wowf|1\n"):
                file.write_text(malformed)
                with self.subTest(malformed=malformed), self.assertRaises(ValueError):
                    check_client(wow, root / "out", recipe)


if __name__ == "__main__":
    unittest.main()
