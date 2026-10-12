import importlib.util
from pathlib import Path
import unittest
spec = importlib.util.spec_from_file_location("prepare", Path(__file__).parents[1]/"prepare-isolated-ci.py")
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)

class TargetTests(unittest.TestCase):
    def test_owned_uuid_root_accepted(self):
        value = "/private/var/folders/test/T/lampyris-imk-7bb55aa3-bc3d-431a-98bc-16161a4b5acc"
        self.assertEqual(str(prepare.target_identity(value)), value)
    def test_real_data_relative_traversal_and_bad_uuid_refused(self):
        for value in ["/Users/user/Library/Application Support/Lampyris", "relative", "/private/var/folders/test/../lampyris-imk-7bb55aa3-bc3d-431a-98bc-16161a4b5acc", "/private/var/folders/test/T/lampyris-imk-invalid"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                prepare.target_identity(value)

if __name__ == "__main__":
    unittest.main()
