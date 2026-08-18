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
PYNEAPPLE_SOURCE = API_SOURCE.with_name('pyneapple_objc.py')
PROVIDER_SOURCE = (
    API_SOURCE.parents[2]
    / 'extractor'
    / 'ytjsc.py'
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

    def test_python_managed_blocks_are_copied_as_stack_blocks(self):
        source = PYNEAPPLE_SOURCE.read_text(encoding='utf-8')

        self.assertIn("self.p_NSConcreteStackBlock = self._system(b'_NSConcreteStackBlock').value", source)
        self.assertIn('isa=pyneapple.p_NSConcreteStackBlock', source)
        self.assertNotIn('p_NSConcreteMallocBlock', source)

    def test_python_managed_blocks_use_complete_objective_c_abi_signatures(self):
        source = API_SOURCE.read_text(encoding='utf-8')

        self.assertIn("_pycb_real, None, POINTER(ObjCBlock), signature=b'v@?'", source)
        self.assertIn("signature=b'v@?@@'", source)

    def test_current_run_loop_coroutines_resume_without_foreign_run_loop_blocks(self):
        source = API_SOURCE.read_text(encoding='utf-8')

        self.assertIn('schedule_steps=False', source)
        self.assertIn('if schedule_steps:', source)
        self.assertIn('scheduled()', source)

    def test_embedded_ios_prefers_the_native_javascript_runner(self):
        source = PROVIDER_SOURCE.read_text(encoding='utf-8')

        self.assertIn("getattr(builtins, '__youtubedl_ios_run_javascript', None)", source)
        self.assertIn('result, err = native_runner(stdin)', source)


if __name__ == '__main__':
    unittest.main()
