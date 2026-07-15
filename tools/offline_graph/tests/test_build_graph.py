import gzip
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load_module(name: str, file_name: str):
    specification = importlib.util.spec_from_file_location(name, ROOT / file_name)
    module = importlib.util.module_from_spec(specification)
    assert specification.loader is not None
    sys.modules[name] = module
    specification.loader.exec_module(module)
    return module


build_graph = load_module("build_graph", "build_graph.py")
create_manifest = load_module("create_manifest", "create_manifest.py")


class BuildGraphTests(unittest.TestCase):
    def setUp(self):
        self.region = {
            "id": "test-region",
            "name": "Test Region",
            "detail": "Fixture roads",
            "bounds": {"south": -37.0, "west": 174.0, "north": -36.0, "east": 175.0},
            "version": 1,
            "formatVersion": 1,
            "encoding": "gzip-json",
            "updatedAt": "2026-07-15T10:00:00Z",
        }
        self.fixture = Path(__file__).parent / "fixtures" / "sample.osm"

    def test_compiler_preserves_legal_direction_and_restrictions(self):
        graph = build_graph.compile_graph(self.fixture, self.region, "2026-07-15T10:00:00Z")

        self.assertEqual([node["id"] for node in graph["nodes"]], [1, 2, 3, 4, 5])
        way_ids = [edge["wayID"] for edge in graph["edges"]]
        self.assertNotIn(102, way_ids)
        self.assertNotIn(103, way_ids)
        self.assertIn(104, way_ids)
        reverse_lane = [edge for edge in graph["edges"] if edge["wayID"] == 101]
        self.assertEqual([(edge["sourceNodeID"], edge["destinationNodeID"]) for edge in reverse_lane], [(4, 3)])
        node_restriction = next(item for item in graph["turnRestrictions"] if item["sourceTag"] == "no_left_turn")
        self.assertEqual(node_restriction["viaNodeID"], 3)
        self.assertEqual(node_restriction["viaWayIDs"], [])
        way_restriction = next(item for item in graph["turnRestrictions"] if item["sourceTag"] == "only_straight_on")
        self.assertIsNone(way_restriction["viaNodeID"])
        self.assertEqual(way_restriction["viaWayIDs"], [101])
        self.assertEqual(way_restriction["kind"], "only")
        coast_road = next(edge for edge in graph["edges"] if edge["wayID"] == 100)
        self.assertEqual(coast_road["maximumSpeedKPH"], 80.0)
        self.assertEqual(coast_road["surface"], "asphalt")

    def test_gzip_output_is_deterministic_and_round_trips(self):
        graph = build_graph.compile_graph(self.fixture, self.region, "2026-07-15T10:00:00Z")
        payload = json.dumps(graph, sort_keys=True, separators=(",", ":")).encode("utf-8")
        first = build_graph.deterministic_gzip(payload)
        second = build_graph.deterministic_gzip(payload)

        self.assertEqual(first, second)
        self.assertEqual(json.loads(gzip.decompress(first)), graph)

    def test_manifest_uses_pack_bytes_and_digest(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            packs = directory / "packs"
            packs.mkdir()
            pack = packs / "test-region-v1.mlgraph"
            pack.write_bytes(b"pack")
            regions = directory / "regions.json"
            regions.write_text(json.dumps({"schemaVersion": 1, "regions": [self.region]}), encoding="utf-8")

            configuration = json.loads(regions.read_text(encoding="utf-8"))
            region = configuration["regions"][0]
            self.assertEqual(region["id"], "test-region")
            self.assertEqual(create_manifest.digest(pack), "4862f447f2c7f272fa2f4aaf89dadb3b1ac09105bd5864f8d1a0c9452bb0a226")

    def test_checked_in_region_configuration_matches_fixture(self):
        configured = build_graph.load_region(Path(__file__).parent / "fixtures" / "regions.json", "test-region")
        self.assertEqual(configured, self.region)


if __name__ == "__main__":
    unittest.main()
