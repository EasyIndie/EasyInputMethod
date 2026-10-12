"""Verify ownership checks for physical-source diagnostic cleanup."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
spec = importlib.util.spec_from_file_location('probe', Path(__file__).with_name('run-physical-source-probe.py'))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

class ManifestTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name)
        (self.app/'Contents').mkdir()
        (self.app/'Contents/file').write_bytes(b'owned')

    def test_changed_bytes_and_permissions_change_identity(self):
        baseline = probe.manifest(self.app)
        (self.app/'Contents/file').write_bytes(b'changed')
        self.assertNotEqual(baseline, probe.manifest(self.app))
        baseline = probe.manifest(self.app)
        (self.app/'Contents/file').chmod(0o700)
        self.assertNotEqual(baseline, probe.manifest(self.app))

    def test_symlink_refused(self):
        (self.app/'external').symlink_to('/tmp')
        with self.assertRaises(ValueError):
            probe.manifest(self.app)

    def test_added_empty_directory_changes_identity(self):
        baseline = probe.manifest(self.app)
        (self.app/'unknown').mkdir()
        self.assertNotEqual(baseline, probe.manifest(self.app))

if __name__ == '__main__':
    unittest.main()
