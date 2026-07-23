import importlib.machinery
import importlib.util
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RENDERER_SOURCE = (ROOT / "bin" / "tmux-status-observatory").read_text()
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
        for direction in ("expand", "collapse"):
            for phase in (0.1, 0.25, 0.5, 0.75, 0.9):
                frame = SWEEP.transition_text(self.layout, phase, direction)
                self.assertNotIn("  ", frame)
                self.assertNotIn("#[range=", frame)
                self.assertNotIn("#[norange]", frame)
                self.assertTrue(frame.startswith("成都·新都 34°C阴"))
                self.assertTrue((frame + fixed_right).endswith(fixed_right))

    def test_renderer_keeps_range_markers_out_of_animated_left_frames(self):
        self.assertIn("render_status_triplet 0 0 left", RENDERER_SOURCE)
        self.assertIn("render_status_triplet 1 0 left", RENDERER_SOURCE)
        self.assertNotIn("render_status_triplet 0 1 left", RENDERER_SOURCE)
        self.assertNotIn("render_status_triplet 1 1 left", RENDERER_SOURCE)

    def test_transition_payload_preserves_settled_click_range(self):
        closed = "成都·新都 34°C阴"
        opened = f"{closed} | 35°C晴·54%雨 36°C雷阵雨·70%雨"
        fixed_right = " | 日出 06:16 日落 20:05 | 14:31 2026-07-23 周四"
        target = f"#[range=user|weather]{opened}#[norange]{fixed_right}"
        fields = [closed] * 3 + [opened] * 3 + [fixed_right] * 3 + [target] * 3

        payload = SWEEP.parse_transition_payload("\0".join(fields).encode())

        self.assertEqual(payload.target_frames["medium"], target)
        self.assertEqual(payload.fixed_right_frames["wide"], fixed_right)

    def test_transition_payload_rejects_range_markers_in_animated_frames(self):
        fields = ["成都·新都 34°C阴"] * 12
        fields[3] = "#[range=user|weather]成都·新都 34°C阴#[norange]"

        with self.assertRaisesRegex(ValueError, "plain text"):
            SWEEP.parse_transition_payload("\0".join(fields).encode())

    def test_display_width_is_unicode_aware(self):
        self.assertEqual(SWEEP.build_layout("周四").width, 4)
        self.assertEqual(SWEEP.build_layout("🐼").width, 2)


if __name__ == "__main__":
    unittest.main()
