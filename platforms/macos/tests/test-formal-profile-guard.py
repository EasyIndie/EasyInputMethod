"""Account isolation is necessary but never sufficient for formal IMK acceptance."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('profile_guard', Path(__file__).with_name('formal-profile-guard.py'))
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class ProfileTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.home = self.root / 'test-account'
        self.home.mkdir(mode=0o700)
        self.uid = os.geteuid()
        self.candidate = self.root / 'candidate.zip'
        self.candidate.write_bytes(b'synthetic candidate, not a signed product')
        self.plan = {'schema': 1, 'scope': 'separate-account-preflight', 'operator_uid': self.uid + 1,
                     'operator_home': str(self.root / 'operator'), 'candidate_sha256': guard.digest(self.candidate), 'candidate_commit': 'a' * 40}
        self.account = patch.object(guard, 'account', return_value=(self.uid, self.home))
        self.account.start()
        self.addCleanup(self.account.stop)
        self.environment = patch.dict(os.environ, {'HOME': str(self.home)})
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def data(self):
        path = self.home / 'Library/Application Support/Lampyris'
        path.mkdir(parents=True, mode=0o700)
        return path

    def test_missing_data_is_read_only_and_not_formal_pass(self):
        result = guard.verify(self.plan, self.candidate)
        self.assertEqual(result['status'], 'PROFILE_READY')
        self.assertEqual(result['formal_result'], 'BLOCKED')
        self.assertFalse(result['desktop_actions_executed'])
        self.assertFalse((self.home / 'Library').exists())

    def test_same_account_or_root_is_blocked(self):
        self.plan['operator_uid'] = self.uid
        with self.assertRaises(ValueError):
            guard.verify(self.plan, self.candidate)
        self.plan['operator_uid'] += 1
        with patch.object(guard, 'account', return_value=(0, self.home)):
            with self.assertRaises(ValueError):
                guard.verify(self.plan, self.candidate)

    def test_fake_home_and_nested_home_are_blocked(self):
        with patch.dict(os.environ, {'HOME': str(self.root)}):
            with self.assertRaises(ValueError):
                guard.verify(self.plan, self.candidate)
        self.plan['operator_home'] = str(self.root)
        with self.assertRaises(ValueError):
            guard.verify(self.plan, self.candidate)

    def test_linked_library_and_dangling_data_are_blocked(self):
        (self.home / 'Library').symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(ValueError):
            guard.verify(self.plan, self.candidate)
        (self.home / 'Library').unlink()
        support = self.home / 'Library/Application Support'
        support.mkdir(parents=True)
        (support / 'Lampyris').symlink_to(self.root / 'missing')
        with self.assertRaises(ValueError):
            guard.verify(self.plan, self.candidate)

    def test_linked_and_hardlinked_files_are_blocked(self):
        data = self.data()
        original = self.root / 'original'
        original.write_bytes(b'do not modify')
        file = data / 'config.toml'
        file.symlink_to(original)
        with self.assertRaises(ValueError):
            guard.verify(self.plan, self.candidate)
        file.unlink()
        os.link(original, file)
        with self.assertRaises(ValueError):
            guard.verify(self.plan, self.candidate)
        self.assertEqual(original.read_bytes(), b'do not modify')

    def test_writable_by_others_and_wrong_owner_are_blocked(self):
        data = self.data()
        data.chmod(0o777)
        with self.assertRaises(ValueError):
            guard.verify(self.plan, self.candidate)
        data.chmod(0o700)
        with patch.object(guard, 'account', return_value=(self.uid + 2, self.home)):
            with self.assertRaises(ValueError):
                guard.verify(self.plan, self.candidate)

    def test_candidate_drift_and_bad_identity_are_blocked(self):
        self.candidate.write_bytes(b'changed')
        with self.assertRaises(ValueError):
            guard.verify(self.plan, self.candidate)
        self.plan['candidate_commit'] = ''
        with self.assertRaises(ValueError):
            guard.verify(self.plan, self.candidate)

    def test_existing_files_are_hashed_without_writing(self):
        data = self.data()
        file = data / 'config.toml'
        file.write_bytes(b'mode = "mixed"\n')
        before = file.stat()
        result = guard.verify(self.plan, self.candidate)
        self.assertEqual(result['data_before']['config.toml'], guard.digest(file))
        self.assertEqual(file.stat().st_mtime_ns, before.st_mtime_ns)
        self.assertEqual(file.read_bytes(), b'mode = "mixed"\n')

    def test_bind_validates_commit_and_cli_refuses_overwrite(self):
        with self.assertRaises(ValueError):
            guard.binding(self.candidate, 'short')
        plan = self.root / 'bound.json'
        argv = ['guard', 'bind', '--candidate', str(self.candidate), '--plan', str(plan), '--commit', 'b' * 40]
        with patch('sys.argv', argv):
            self.assertEqual(guard.main(), 0)
        before = plan.read_bytes()
        with patch('sys.argv', argv):
            self.assertEqual(guard.main(), 3)
        self.assertEqual(plan.read_bytes(), before)
        self.assertEqual(plan.stat().st_mode & 0o777, 0o600)
        self.assertEqual(json.loads(before)['operator_uid'], self.uid)


if __name__ == '__main__':
    unittest.main()
