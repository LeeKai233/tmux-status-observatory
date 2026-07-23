import importlib.machinery
import importlib.util
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LOADER = importlib.machinery.SourceFileLoader(
    "tmux_status_sweep", str(ROOT / "bin" / "tmux-status-sweep")
)
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
SWEEP = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[LOADER.name] = SWEEP
SPEC.loader.exec_module(SWEEP)


class SweepTransitionTests(unittest.TestCase):
    def setUp(self):
        self.closed = SWEEP.build_layout("成都·新都 34°C阴")
        self.opened = SWEEP.build_layout(
            "成都·新都 34°C阴 | 35°C晴·54%雨 36°C雷阵雨·70%雨"
        )
        self.layout = SWEEP.build_transition_layout(self.closed, self.opened)

    def test_insertion_is_left_of_anchor(self):
        self.assertEqual(self.layout.prefix, tuple(SWEEP.split_clusters("成都·新都 34°C阴")))
        self.assertEqual(self.layout.suffix, ())
        self.assertGreater(self.layout.insertion_width, 0)

    def test_expand_and_collapse_endpoints(self):
        self.assertEqual(
            SWEEP.transition_text(self.layout, 0.0, "expand"),
            "成都·新都 34°C阴",
        )
        self.assertEqual(
            SWEEP.transition_text(self.layout, 1.0, "expand"),
            "成都·新都 34°C阴 | 35°C晴·54%雨 36°C雷阵雨·70%雨",
        )
        self.assertEqual(
            SWEEP.transition_text(self.layout, 0.0, "collapse"),
            "成都·新都 34°C阴 | 35°C晴·54%雨 36°C雷阵雨·70%雨",
        )
        self.assertEqual(
            SWEEP.transition_text(self.layout, 1.0, "collapse"),
            "成都·新都 34°C阴",
        )

    def test_progress_never_inserts_padding(self):
        fixed_right = " | 日出 06:16 日落 20:05 | NASA M3.6 | 14:31 2026-07-23 周四"
        for phase in (0.1, 0.25, 0.5, 0.75, 0.9):
            frame = SWEEP.transition_text(self.layout, phase, "expand")
            self.assertNotIn("  ", frame)
            self.assertTrue(frame.startswith("成都·新都 34°C阴"))
            self.assertTrue((frame + fixed_right).endswith(fixed_right))

    def test_display_width_is_unicode_aware(self):
        self.assertEqual(SWEEP.build_layout("周四").width, 4)
        self.assertEqual(SWEEP.build_layout("🐼").width, 2)


if __name__ == "__main__":
    unittest.main()
