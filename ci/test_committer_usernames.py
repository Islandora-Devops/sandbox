import pathlib
import subprocess
import unittest

SCRIPT = pathlib.Path(__file__).with_name("committer-usernames.py")


class CommitterTableTest(unittest.TestCase):
    def parse(self, html):
        return subprocess.run(["python3", str(SCRIPT)], input=html, text=True, capture_output=True)

    def test_only_current_committers_are_used(self):
        result = self.parse('''<h2 id="committers">Committers</h2><table>
          <tr><th>Name</th><th>Organization</th><th>Github username</th></tr>
          <tr><td>Joe</td><td>Lehigh</td><td><a>joecorall</a></td></tr></table>
          <h2 id="emeritus-committers">Emeritus</h2><table><tr><td>other</td></tr></table>''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "joecorall\n")

    def test_missing_or_invalid_table_fails(self):
        for html in ('<h2 id="committers">Committers</h2>', '''<h2 id="committers">Committers</h2><table>
          <tr><th>Name</th><th>Organization</th><th>Github username</th></tr>
          <tr><td>Joe</td><td>Lehigh</td><td>bad/user</td></tr></table>'''):
            self.assertNotEqual(self.parse(html).returncode, 0)


if __name__ == "__main__":
    unittest.main()
