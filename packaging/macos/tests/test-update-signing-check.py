"""The manual signing diagnostic must not publish or upload credential material."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / '.github/workflows/update-signing-check.yml'


class SigningDiagnosticWorkflowTests(unittest.TestCase):
    def test_main_only_signed_diagnostic_artifact(self):
        text = WORKFLOW.read_text()
        self.assertIn("if: github.ref == 'refs/heads/main'", text)
        self.assertIn('targets: aarch64-apple-darwin, x86_64-apple-darwin', text)
        self.assertIn('codesign --verify --strict --deep "$app"', text)
        self.assertIn('xcrun stapler validate "$app"', text)
        self.assertIn('spctl --assess --type execute "$app"', text)
        self.assertIn('printf \'%s\\n\' "$GITHUB_SHA" > "$work/SOURCE-COMMIT.txt"', text)
        self.assertIn('Lampyris-updater-diagnostic-${{ github.sha }}', text)
        self.assertIn('retention-days: 7', text)
        self.assertIn('path: |\n            packaging/out/update-signing-check/LampyrisUpdateCheck-diagnostic.zip\n', text)
        self.assertNotIn('path: packaging/out/update-signing-check/*', text)
        self.assertNotIn('gh release create', text)


if __name__ == '__main__':
    unittest.main()
