"""Offline checks using real Git histories and Elixir source parsing; no writes to Hex."""
import json
import hashlib
import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
CHECK = ROOT / "bin/docs-release-check"
HELPER = ROOT / "test/support/documentation_runtime_identity.exs"
spec = importlib.util.spec_from_file_location("documentation_publication", ROOT / "test/support/documentation_publication.py")
publication = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publication)


class DocumentationReleaseTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="exagent-docs-release-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.write("mix.exs", '''defmodule Example.MixProject do
  @version "2.0.0"
  def project, do: [version: @version, deps: [{:req_llm, "~> 1.26"}], docs: docs()]
  defp docs, do: [extras: ["README.md"]]
end
''')
        self.write("lib/example.ex", '''defmodule Example do
  @moduledoc "A documented module."
  @doc "Return a number."
  @spec run() :: integer()
  def run, do: 1
end
''')
        self.write("mix.lock", "%{}\n")
        self.write("config/config.exs", "import Config\nconfig :example, limit: 1\n")
        self.write("examples/demo.exs", "Example.run()\n")
        self.write("examples/README.md", "# Example\n")
        self.write("README.md", "# Example package\n")
        target = self.root / "test/support/documentation_runtime_identity.exs"
        target.parent.mkdir(parents=True)
        shutil.copy2(HELPER, target)
        self.git("init", "--quiet", "--initial-branch=main")
        self.commit()
        self.git("tag", "v2.0.0")
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")

    def write(self, path, value):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(value)

    def replace(self, path, old, new):
        target = self.root / path
        self.assertIn(old, target.read_text())
        target.write_text(target.read_text().replace(old, new))

    def git(self, *args):
        result = subprocess.run(["git", *args], cwd=self.root, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def commit(self):
        self.git("add", ".")
        self.git("-c", "user.name=Documentation test", "-c", "user.email=docs@example.invalid",
                 "commit", "--quiet", "-m", "fixture")

    def check(self, success=False, tag="v2.0.0", prepare=True, reason=None):
        command = ["python3", str(CHECK), tag] + (["--prepare"] if prepare else [])
        result = subprocess.run(command, cwd=self.root, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0 if success else 1, result.stderr)
        if reason:
            self.assertIn(reason, result.stderr)
        return result

    def test_original_release_and_documentation_only_update(self):
        self.check(success=True)
        self.replace("lib/example.ex", "A documented module.", "Updated usage instructions.")
        self.replace("lib/example.ex", "Return a number.", "Returns a number to the caller.")
        self.replace("mix.exs", '[extras: ["README.md"]]', '[extras: ["README.md", "guide.md"]]')
        self.write("examples/README.md", "# Updated usage\n")
        self.write("README.md", "# New documentation\n")
        result = self.check(success=True)
        self.assertEqual(json.loads(result.stdout)["mode"], "prepare")

    def test_executable_body_change_rejected(self):
        self.replace("lib/example.ex", "def run, do: 1", "def run, do: 2")
        self.check(reason="executable source changed: lib/example.ex")

    def test_public_contract_change_rejected(self):
        self.replace("lib/example.ex", "@spec run() :: integer()", "@spec run() :: float()")
        self.check(reason="executable source changed: lib/example.ex")

    def test_quoted_documentation_is_executable_macro_data(self):
        self.write("lib/example.ex", '''defmodule Example do
  defmacro generate do
    quote do
      @doc "Generated contract"
      def run, do: 1
    end
  end
end
''')
        self.commit()
        self.git("tag", "--force", "v2.0.0")
        self.replace("lib/example.ex", "Generated contract", "Changed generated contract")
        self.check(reason="executable source changed: lib/example.ex")

    def test_dependency_and_application_configuration_changes_rejected(self):
        for path, old, new in [("mix.lock", "%{}", '%{dependency: "changed"}'),
                               ("config/config.exs", "limit: 1", "limit: 2"),
                               ("examples/demo.exs", "Example.run()", 'IO.puts("changed")')]:
            with self.subTest(path=path):
                self.replace(path, old, new)
                self.check(reason="runtime/dependency input changed")
                self.git("restore", path)

    def test_project_dependency_change_rejected(self):
        self.replace("mix.exs", "~> 1.26", "~> 1.27")
        self.check(reason="executable source changed: mix.exs")

    def test_new_untracked_runtime_module_rejected(self):
        self.write("lib/extra.ex", "defmodule Extra do\n  def run, do: 42\nend\n")
        self.check(reason="runtime file inventory changed")

    def test_deleted_runtime_module_rejected(self):
        self.git("rm", "lib/example.ex")
        self.check(reason="runtime file inventory changed")

    def test_dynamic_doc_expression_cannot_hide_execution(self):
        self.replace("lib/example.ex", '@moduledoc "A documented module."',
                     '@moduledoc File.read!("README.md")')
        self.commit()
        self.git("tag", "--force", "v2.0.0")
        self.write("README.md", "# Updated prose\n")
        self.check(success=True)
        self.replace("lib/example.ex", 'File.read!("README.md")', 'File.read!("another.md")')
        self.check(reason="executable source changed: lib/example.ex")

    def test_invalid_or_mismatched_version_rejected(self):
        for tag in ["v2.0.0-rc.1", "v2.0.0;echo unsafe", "v02.0.0", "v2.0.0\n"]:
            with self.subTest(tag=tag):
                self.check(tag=tag, reason="canonical stable")
        self.replace("mix.exs", '@version "2.0.0"', '@version "2.0.1"')
        self.check(reason="version does not match")

    def test_publication_requires_clean_main_checkout(self):
        self.write("README.md", "Uncommitted docs\n")
        self.check(prepare=False, reason="must be clean")
        self.commit()
        self.check(prepare=False, reason="merge-base")


class DocumentationReadbackTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="exagent-docs-readback-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.package = b"the original immutable package"
        self.metadata = {"version": "2.0.0", "docs_commit": "source-commit",
                         "hex_checksum": hashlib.sha256(self.package).hexdigest()}
        self.names = ["index.html", "welcome.html", "documentation.html", "agents.md", "llms.txt",
                      "readme.html", "dist/sidebar_items-revision.js"]
        for name in self.names:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(b"<html><head></head><body>current manual</body></html>")

    def fetch(self, url):
        if url.endswith(".tar"):
            return self.package
        name = url.split("/2.0.0/", 1)[1].split("?", 1)[0]
        value = (self.root / name).read_bytes()
        if name.endswith(".html"):
            value = value.replace(b"</head>", publication.HEXDOCS_ANALYTICS + b"</head>")
        return value

    def test_generated_content_with_exact_host_insertion_passes(self):
        with patch.object(publication, "fetch", self.fetch):
            publication.verify(self.metadata, self.root)

    def test_stale_docs_fail_even_when_version_and_package_match(self):
        def stale(url):
            return self.fetch(url).replace(b"current manual", b"previous manual") if not url.endswith(".tar") else self.package
        with patch.object(publication, "fetch", stale), patch.object(publication.time, "sleep"):
            with self.assertRaisesRegex(ValueError, "readback failed"):
                publication.verify(self.metadata, self.root)

    def test_replaced_package_fails_before_doc_readback(self):
        with patch.object(publication, "fetch", return_value=b"different package"):
            with self.assertRaisesRegex(ValueError, "package bytes changed"):
                publication.verify(self.metadata, self.root)

    def test_unknown_html_injection_is_not_ignored(self):
        original = (self.root / "index.html").read_bytes()
        actual = self.fetch("https://hexdocs.pm/exagent/2.0.0/index.html")
        self.assertEqual(publication.documentation_bytes("index.html", actual), original)
        actual = actual.replace(b"</head>", b"<script>unknown()</script></head>")
        self.assertNotEqual(publication.documentation_bytes("index.html", actual), original)


if __name__ == "__main__":
    unittest.main()
