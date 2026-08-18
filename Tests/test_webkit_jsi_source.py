import ast
import unittest
from pathlib import Path


API_SOURCE = (
    Path(__file__).resolve().parents[1]
    / 'Sources'
    / 'YoutubeDL'
    / 'Resources'
    / 'yt_dlp_plugins'
    / 'webkit_jsi'
    / 'lib'
    / 'api.py'
)


class WebKitJSISourceTests(unittest.TestCase):
    def test_generator_priming_is_not_removed_by_optimized_python(self):
        source = API_SOURCE.read_text(encoding='utf-8')
        tree = ast.parse(source)

        priming_calls_in_asserts = [
            node
            for assertion in ast.walk(tree)
            if isinstance(assertion, ast.Assert)
            for node in ast.walk(assertion.test)
            if (
                isinstance(node, ast.Call)
                and isinstance(node.func, ast.Attribute)
                and node.func.attr == 'send'
                and isinstance(node.func.value, ast.Name)
                and node.func.value.id == 'gen_run'
            )
        ]

        self.assertEqual(priming_calls_in_asserts, [])
        self.assertIn('initial_state = gen_run.send(None)', source)


if __name__ == '__main__':
    unittest.main()
