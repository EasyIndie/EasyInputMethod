import importlib.util
from pathlib import Path
import unittest
spec = importlib.util.spec_from_file_location("prepare", Path(__file__).parents[1]/"prepare-isolated-ci.py")
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)

UUID = "7bb55aa3-bc3d-431a-98bc-16161a4b5acc"

class TargetTests(unittest.TestCase):
    def test_owned_uuid_root_accepted(self):
        for value in [f"/private/var/folders/test/T/lampyris-imk-{UUID}",
                      f"/private/var/folders/x7/hhbm75rn6vz_37yjj5rsq9yc0000gn/T/lampyris-imk-{UUID}",
                      f"/private/tmp/lampyris-imk-{UUID}",
                      f"/var/tmp/lampyris-imk-{UUID}",
                      f"/var/folders/x7/hhbm75rn6vz_37yjj5rsq9yc0000gn/T/lampyris-imk-{UUID}"]:
            with self.subTest(value=value):
                self.assertEqual(str(prepare.target_identity(value)), value)
    def test_real_data_relative_traversal_and_bad_uuid_refused(self):
        for value in [f"/Users/user/Library/Application Support/Lampyris/lampyris-imk-{UUID}", "relative",
                      f"/private/var/folders/test/../lampyris-imk-{UUID}", f"/private/var/folders/test/T/lampyris-imk-invalid",
                      f"/private/var/folders/test/C/lampyris-imk-{UUID}", f"/tmp/../tmp/lampyris-imk-{UUID}", f"/private/tmp/sub/lampyris-imk-{UUID}"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                prepare.target_identity(value)
    def test_persistent_root_requires_explicit_development(self):
        value = f"/Users/user/Library/Application Support/LampyrisIMKDev/lampyris-imk-{UUID}"
        self.assertEqual(str(prepare.target_identity(value, True)), value)
        with self.assertRaises(ValueError):
            prepare.target_identity(value)
        for bad in [f"/private/tmp/lampyris-imk-{UUID}", value.replace("LampyrisIMKDev", "Lampyris"), value.replace("/Users/user", "/Applications")]:
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                prepare.target_identity(bad, True)

    def test_arch_request(self):
        for value in ["native", "", None]:
            self.assertEqual(prepare.target_arch(value), "native")
        for value in ["arm64", "x86_64", "universal"]:
            self.assertEqual(prepare.target_arch(value), value)
        for value in ["armv7", "i386", "*", "x86", "../x86_64"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                prepare.target_arch(value)

if __name__ == "__main__":
    unittest.main()
