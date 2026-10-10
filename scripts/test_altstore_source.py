import unittest
import importlib.util
from pathlib import Path
spec = importlib.util.spec_from_file_location("altstore_source", Path(__file__).with_name("altstore-source.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
make_source = module.make_source


def release(tag, prerelease=False, ipa=True, draft=False):
    return {"tagName": tag, "isPrerelease": prerelease, "isDraft": draft,
            "publishedAt": "2026-10-11T00:00:00Z", "body": "Release notes",
            "assets": [{"name": "SpicyLyrics-unsigned.ipa", "url": "https://example.com/app.ipa", "size": 123}] if ipa else []}


class ChannelTests(unittest.TestCase):
    def setUp(self):
        self.releases = [release("v0.3.1-alpha.9", True), release("v0.3.0"),
                         release("v0.3.1-beta.11", True), release("v0.3.1-alpha.10", True),
                         release("v0.4.0", ipa=False), release("v9.0.0", draft=True),
                         release("preview", True)]

    def test_stable_filters(self):
        versions = make_source("owner/repo", "stable", self.releases)["apps"][0]["versions"]
        self.assertEqual([v["version"] for v in versions], ["0.3.0"])

    def test_testing_order_and_ipa_versions(self):
        versions = make_source("owner/repo", "testing", self.releases)["apps"][0]["versions"]
        self.assertEqual([v.get("buildVersion") for v in versions], ["11", "10", "9", None])
        self.assertEqual(versions[0]["version"], "0.3.1")
        self.assertIn("Beta", versions[0]["localizedDescription"])

    def test_stable_supersedes_same_version_prereleases(self):
        versions = make_source("owner/repo", "testing", self.releases + [release("v0.3.1")])["apps"][0]["versions"]
        self.assertNotIn("buildVersion", versions[0])
        self.assertEqual(versions[0]["version"], "0.3.1")

    def test_sources_unique_and_same_app(self):
        stable = make_source("owner/repo", "stable", self.releases)
        testing = make_source("owner/repo", "testing", self.releases)
        self.assertNotEqual(stable["identifier"], testing["identifier"])
        self.assertEqual(stable["identifier"], "com.spicylyrics.unofficial.source")
        self.assertEqual(stable["apps"][0]["bundleIdentifier"], testing["apps"][0]["bundleIdentifier"])

    def test_empty_source_fails(self):
        with self.assertRaises(ValueError):
            make_source("owner/repo", "stable", [release("v0.3.1-alpha.10", True)])


if __name__ == "__main__":
    unittest.main()
