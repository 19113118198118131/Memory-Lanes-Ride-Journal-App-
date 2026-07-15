import importlib.util
import json
import sys
import tempfile
import unittest
import zlib
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
audit_graph = load_module("audit_graph", "audit_graph.py")


class BuildGraphTests(unittest.TestCase):
    def setUp(self):
        fixture_directory = Path(__file__).parent / "fixtures"
        self.fixture = fixture_directory / "sample.osm"
        self.regions_fixture = fixture_directory / "regions.json"
        configuration = json.loads(self.regions_fixture.read_text(encoding="utf-8"))
        self.region = configuration["regions"][0]

    def write_graph(self, directory: Path, graph: dict) -> Path:
        payload = json.dumps(graph, sort_keys=True, separators=(",", ":")).encode("utf-8")
        path = directory / "test-region-v1.mlgraph"
        path.write_bytes(build_graph.deterministic_zlib(payload))
        return path

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

    def test_zlib_output_is_deterministic_and_round_trips(self):
        graph = build_graph.compile_graph(self.fixture, self.region, "2026-07-15T10:00:00Z")
        payload = json.dumps(graph, sort_keys=True, separators=(",", ":")).encode("utf-8")
        first = build_graph.deterministic_zlib(payload)
        second = build_graph.deterministic_zlib(payload)

        self.assertEqual(first, second)
        self.assertEqual(json.loads(zlib.decompress(first)), graph)

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
        configured = build_graph.load_region(self.regions_fixture, "test-region")
        self.assertEqual(configured, self.region)

    def test_graph_audit_measures_connectivity_and_route_probes(self):
        graph = build_graph.compile_graph(self.fixture, self.region, "2026-07-15T10:00:00Z")
        with tempfile.TemporaryDirectory() as directory_name:
            pack = self.write_graph(Path(directory_name), graph)
            report = audit_graph.audit(pack, self.region)

        self.assertEqual(report["result"], "passed")
        self.assertEqual(report["graph"]["nodes"], 5)
        self.assertEqual(report["graph"]["largestWeakComponentRatio"], 1.0)
        self.assertEqual([(route["from"], route["to"]) for route in report["routes"]], [("end", "start")])
        self.assertGreater(report["routes"][0]["distanceMeters"], 0)

    def test_graph_audit_rejects_fragmented_release(self):
        graph = build_graph.compile_graph(self.fixture, self.region, "2026-07-15T10:00:00Z")
        graph["edges"] = [edge for edge in graph["edges"] if edge["wayID"] != 104]
        replacements = []
        for way_id, source, destination in [(900, 1, 2), (901, 2, 1)]:
            replacement = dict(graph["edges"][0])
            replacement.update({"wayID": way_id, "sourceNodeID": source, "destinationNodeID": destination})
            replacements.append(replacement)
        graph["edges"].extend(replacements)
        way_restriction = next(
            restriction
            for restriction in graph["turnRestrictions"]
            if restriction["sourceTag"] == "only_straight_on"
        )
        way_restriction["toWayID"] = 900
        with tempfile.TemporaryDirectory() as directory_name:
            pack = self.write_graph(Path(directory_name), graph)
            with self.assertRaisesRegex(audit_graph.GraphAuditError, "Largest weak component"):
                audit_graph.audit(pack, self.region)


if __name__ == "__main__":
    unittest.main()
