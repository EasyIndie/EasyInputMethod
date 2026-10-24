"""The isolated update drill must stay test-only, main-only and off the production keys."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / '.github/workflows/isolated-update-drill.yml'


class IsolatedUpdateDrillTests(unittest.TestCase):
    def setUp(self):
        self.text = WORKFLOW.read_text()

    def test_main_only_and_test_only(self):
        self.assertEqual(self.text.count("if: github.ref == 'refs/heads/main'"), 2)
        self.assertIn('channel=isolated-drill', self.text)
        self.assertIn('--isolated-root "${root}" --isolated-identity "${identity}"', self.text)
        self.assertIn('--test-build "${TEST_BUILD}"', self.text)
        self.assertNotIn('update-public-key.txt', self.text)
        self.assertNotIn('LAMPYRIS_UPDATE_PRIVATE_KEY', self.text)

    def test_ephemeral_key_is_generated_and_dropped(self):
        self.assertIn('openssl genpkey -algorithm ED25519 -out "${RUNNER_TEMP}/drill-key.pem"', self.text)
        self.assertIn('--private-key "${RUNNER_TEMP}/drill-key.pem"', self.text)
        self.assertIn('rm -f "${RUNNER_TEMP}/drill-key.pem"', self.text)
        self.assertIn('DRILL-PUBLIC-KEY.txt', self.text)

    def test_payload_is_notarized_and_feed_is_the_pages_subpath(self):
        self.assertIn('bash packaging/macos/ci-sign.sh\n', self.text)
        self.assertIn('base="https://input.jokerhub.cn/${DRILL_PATH}"', self.text)
        self.assertIn('ditto platforms/macos/build/Lampyris.app "${RUNNER_TEMP}/LampyrisIMKTest.app"', self.text)
        self.assertIn('site/${DRILL_PATH}', self.text)
        self.assertIn('drill|drill-*)', self.text)
        for forbidden in ('gh release create', 'git tag', 'github.io', '/etc/hosts'):
            self.assertNotIn(forbidden, self.text)

    def test_artifact_is_short_lived_and_signing_is_cleaned_up(self):
        self.assertIn('retention-days: 7', self.text)
        self.assertIn('bash packaging/macos/ci-sign.sh --cleanup', self.text)
        self.assertIn('if-no-files-found: error', self.text)


if __name__ == '__main__':
    unittest.main()
