#!/usr/bin/env python3
"""Audit and benchmark a compiled Memory Lanes offline road graph."""

from __future__ import annotations

import argparse
import heapq
import json
import math
import os
import resource
import sys
import time
import zlib
from collections import Counter, defaultdict
from pathlib import Path


SPATIAL_CELL_DEGREES = 0.02
MAXIMUM_ROUTING_SPEED_METERS_PER_SECOND = 160.0 / 3.6


class GraphAuditError(ValueError):
    pass


class DisjointSet:
    def __init__(self, node_ids: list[int]) -> None:
        self.parent = {node_id: node_id for node_id in node_ids}
        self.size = {node_id: 1 for node_id in node_ids}

    def find(self, node_id: int) -> int:
        root = node_id
        while self.parent[root] != root:
            root = self.parent[root]
        while self.parent[node_id] != node_id:
            next_node = self.parent[node_id]
            self.parent[node_id] = root
            node_id = next_node
        return root

    def union(self, first: int, second: int) -> None:
        first_root = self.find(first)
        second_root = self.find(second)
        if first_root == second_root:
            return
        if self.size[first_root] < self.size[second_root]:
            first_root, second_root = second_root, first_root
        self.parent[second_root] = first_root
        self.size[first_root] += self.size[second_root]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--graph", required=True, type=Path)
    parser.add_argument("--regions", required=True, type=Path)
    parser.add_argument("--region-id", required=True)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def load_region(path: Path, region_id: str) -> dict:
    document = json.loads(path.read_text(encoding="utf-8"))
    matches = [region for region in document.get("regions", []) if region.get("id") == region_id]
    if len(matches) != 1:
        raise GraphAuditError(f"Expected exactly one region named {region_id!r}")
    region = matches[0]
    quality = region.get("quality")
    if not isinstance(quality, dict) or not quality.get("probes") or not quality.get("routePairs"):
        raise GraphAuditError("Region is missing graph quality probes")
    return region


def haversine_meters(first: tuple[float, float], second: tuple[float, float]) -> float:
    latitude1, longitude1 = map(math.radians, first)
    latitude2, longitude2 = map(math.radians, second)
    latitude_delta = latitude2 - latitude1
    longitude_delta = longitude2 - longitude1
    value = (
        math.sin(latitude_delta / 2) ** 2
        + math.cos(latitude1) * math.cos(latitude2) * math.sin(longitude_delta / 2) ** 2
    )
    return 6_371_008.8 * 2 * math.atan2(math.sqrt(value), math.sqrt(max(1 - value, 0)))


def spatial_cell(coordinate: tuple[float, float]) -> tuple[int, int]:
    return (
        math.floor((coordinate[0] + 90) / SPATIAL_CELL_DEGREES),
        math.floor((coordinate[1] + 180) / SPATIAL_CELL_DEGREES),
    )


def nearest_node(
    coordinate: tuple[float, float],
    coordinates: dict[int, tuple[float, float]],
    spatial_cells: dict[tuple[int, int], list[int]],
    maximum_distance_meters: float,
) -> tuple[int, float]:
    center = spatial_cell(coordinate)
    maximum_ring = max(math.ceil(maximum_distance_meters / 1_500), 1) + 1
    nearest_id = None
    nearest_distance = math.inf
    for latitude_offset in range(-maximum_ring, maximum_ring + 1):
        for longitude_offset in range(-maximum_ring, maximum_ring + 1):
            cell = (center[0] + latitude_offset, center[1] + longitude_offset)
            for node_id in spatial_cells.get(cell, []):
                distance = haversine_meters(coordinate, coordinates[node_id])
                if distance < nearest_distance:
                    nearest_id = node_id
                    nearest_distance = distance
    if nearest_id is None or nearest_distance > maximum_distance_meters:
        raise GraphAuditError(
            f"Probe at {coordinate[0]:.5f},{coordinate[1]:.5f} did not snap within "
            f"{maximum_distance_meters:.0f} m"
        )
    return nearest_id, nearest_distance


def route_probe(
    source: int,
    destination: int,
    coordinates: dict[int, tuple[float, float]],
    adjacency: dict[int, list[tuple[int, float, float]]],
    maximum_expanded_nodes: int,
) -> dict:
    queue = [(0.0, 0.0, source)]
    best_cost = {source: 0.0}
    best_distance = {source: 0.0}
    expanded_nodes = 0
    while queue:
        _, route_cost, node_id = heapq.heappop(queue)
        if route_cost > best_cost.get(node_id, math.inf) + 0.000_001:
            continue
        if node_id == destination:
            return {
                "distanceMeters": round(best_distance[node_id], 3),
                "expectedTravelTimeSeconds": round(route_cost, 3),
                "expandedNodes": expanded_nodes,
            }
        expanded_nodes += 1
        if expanded_nodes > maximum_expanded_nodes:
            raise GraphAuditError(f"Route probe exceeded {maximum_expanded_nodes} expanded nodes")
        for next_id, travel_time, distance in adjacency.get(node_id, []):
            next_cost = route_cost + travel_time
            if next_cost + 0.000_001 >= best_cost.get(next_id, math.inf):
                continue
            best_cost[next_id] = next_cost
            best_distance[next_id] = best_distance[node_id] + distance
            heuristic = haversine_meters(coordinates[next_id], coordinates[destination])
            heapq.heappush(
                queue,
                (next_cost + heuristic / MAXIMUM_ROUTING_SPEED_METERS_PER_SECOND, next_cost, next_id),
            )
    raise GraphAuditError(f"No directed road path from node {source} to node {destination}")


def audit(graph_path: Path, region: dict) -> dict:
    started_at = time.perf_counter()
    compressed = graph_path.read_bytes()
    decompression_started = time.perf_counter()
    try:
        payload = zlib.decompress(compressed)
    except zlib.error as error:
        raise GraphAuditError("Graph is not valid zlib data") from error
    decompression_seconds = time.perf_counter() - decompression_started

    parsing_started = time.perf_counter()
    graph = json.loads(payload)
    parsing_seconds = time.perf_counter() - parsing_started
    if graph.get("formatVersion") != region.get("formatVersion"):
        raise GraphAuditError("Graph format version does not match its region")
    if graph.get("regionID") != region.get("id"):
        raise GraphAuditError("Graph region ID does not match its region")
    if graph.get("bounds") != region.get("bounds"):
        raise GraphAuditError("Graph bounds do not match their release configuration")

    nodes = graph.get("nodes")
    edges = graph.get("edges")
    restrictions = graph.get("turnRestrictions")
    if not isinstance(nodes, list) or not isinstance(edges, list) or not isinstance(restrictions, list):
        raise GraphAuditError("Graph arrays are missing")

    indexing_started = time.perf_counter()
    coordinates: dict[int, tuple[float, float]] = {}
    spatial_cells: dict[tuple[int, int], list[int]] = defaultdict(list)
    for node in nodes:
        node_id = node.get("id")
        coordinate = node.get("coordinate", {})
        latitude = coordinate.get("latitude")
        longitude = coordinate.get("longitude")
        if (
            not isinstance(node_id, int)
            or node_id <= 0
            or node_id in coordinates
            or not isinstance(latitude, (int, float))
            or not isinstance(longitude, (int, float))
            or not math.isfinite(latitude)
            or not math.isfinite(longitude)
            or not -90 <= latitude <= 90
            or not -180 <= longitude <= 180
        ):
            raise GraphAuditError("Graph contains an invalid or duplicate node")
        coordinates[node_id] = (latitude, longitude)
        spatial_cells[spatial_cell((latitude, longitude))].append(node_id)

    adjacency: dict[int, list[tuple[int, float, float]]] = defaultdict(list)
    disjoint_set = DisjointSet(list(coordinates))
    road_class_distance: Counter[str] = Counter()
    surface_distance = 0.0
    total_distance = 0.0
    directed_edges = set()
    way_ids = set()
    for edge in edges:
        way_id = edge.get("wayID")
        source = edge.get("sourceNodeID")
        destination = edge.get("destinationNodeID")
        distance = edge.get("distanceMeters")
        travel_time = edge.get("expectedTravelTime")
        road_class = edge.get("roadClass")
        directed_key = (way_id, source, destination)
        if (
            not isinstance(way_id, int)
            or way_id <= 0
            or source not in coordinates
            or destination not in coordinates
            or source == destination
            or not isinstance(distance, (int, float))
            or not isinstance(travel_time, (int, float))
            or not math.isfinite(distance)
            or not math.isfinite(travel_time)
            or distance <= 0
            or travel_time <= 0
            or not isinstance(road_class, str)
            or directed_key in directed_edges
        ):
            raise GraphAuditError("Graph contains an invalid or duplicate directed edge")
        directed_edges.add(directed_key)
        way_ids.add(way_id)
        adjacency[source].append((destination, travel_time, distance))
        disjoint_set.union(source, destination)
        road_class_distance[road_class] += distance
        total_distance += distance
        if edge.get("surface"):
            surface_distance += distance

    for restriction in restrictions:
        from_way = restriction.get("fromWayID")
        to_way = restriction.get("toWayID")
        via_node = restriction.get("viaNodeID")
        via_ways = restriction.get("viaWayIDs")
        if (
            from_way not in way_ids
            or to_way not in way_ids
            or not isinstance(via_ways, list)
            or any(way_id not in way_ids for way_id in via_ways)
            or (via_node is not None and via_node not in coordinates)
            or (via_node is None and not via_ways)
            or restriction.get("kind") not in {"prohibited", "only"}
        ):
            raise GraphAuditError("Graph contains an invalid turn restriction")

    component_sizes = Counter(disjoint_set.find(node_id) for node_id in coordinates)
    largest_component_size = max(component_sizes.values(), default=0)
    largest_component_ratio = largest_component_size / max(len(coordinates), 1)
    indexing_seconds = time.perf_counter() - indexing_started

    quality = region["quality"]
    minimum_nodes = int(quality.get("minimumNodes", 1))
    minimum_edges = int(quality.get("minimumEdges", 1))
    minimum_restrictions = int(quality.get("minimumTurnRestrictions", 0))
    minimum_component_ratio = float(quality.get("minimumLargestWeakComponentRatio", 0))
    if len(nodes) < minimum_nodes:
        raise GraphAuditError(f"Graph has {len(nodes)} nodes; expected at least {minimum_nodes}")
    if len(edges) < minimum_edges:
        raise GraphAuditError(f"Graph has {len(edges)} edges; expected at least {minimum_edges}")
    if len(restrictions) < minimum_restrictions:
        raise GraphAuditError(
            f"Graph has {len(restrictions)} turn restrictions; expected at least {minimum_restrictions}"
        )
    if largest_component_ratio < minimum_component_ratio:
        raise GraphAuditError(
            f"Largest weak component is {largest_component_ratio:.3f}; expected {minimum_component_ratio:.3f}"
        )

    maximum_snap_distance = float(quality.get("maximumProbeSnapDistanceMeters", 2_500))
    snapped_probes = {}
    probe_report = []
    for probe in quality["probes"]:
        probe_id = probe.get("id")
        if not isinstance(probe_id, str) or probe_id in snapped_probes:
            raise GraphAuditError("Quality probes require unique string IDs")
        node_id, distance = nearest_node(
            (float(probe["latitude"]), float(probe["longitude"])),
            coordinates,
            spatial_cells,
            maximum_snap_distance,
        )
        snapped_probes[probe_id] = node_id
        probe_report.append(
            {
                "id": probe_id,
                "name": probe.get("name", probe_id),
                "nodeID": node_id,
                "snapDistanceMeters": round(distance, 3),
            }
        )

    maximum_expanded_nodes = int(quality.get("maximumProbeExpandedNodes", 500_000))
    route_report = []
    routing_started = time.perf_counter()
    for pair in quality["routePairs"]:
        source_id = pair.get("from")
        destination_id = pair.get("to")
        if source_id not in snapped_probes or destination_id not in snapped_probes:
            raise GraphAuditError("Route pair references an unknown quality probe")
        result = route_probe(
            snapped_probes[source_id],
            snapped_probes[destination_id],
            coordinates,
            adjacency,
            maximum_expanded_nodes,
        )
        result.update({"from": source_id, "to": destination_id})
        route_report.append(result)
    routing_seconds = time.perf_counter() - routing_started

    road_class_ratios = {
        key: round(value / total_distance, 6)
        for key, value in sorted(road_class_distance.items())
    }
    peak_resident_memory = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    peak_resident_memory_mb = peak_resident_memory / (1_024 if sys.platform.startswith("linux") else 1_048_576)
    return {
        "schemaVersion": 1,
        "regionID": region["id"],
        "result": "passed",
        "archive": {
            "compressedBytes": len(compressed),
            "inflatedBytes": len(payload),
            "compressionRatio": round(len(compressed) / max(len(payload), 1), 6),
        },
        "graph": {
            "nodes": len(nodes),
            "edges": len(edges),
            "turnRestrictions": len(restrictions),
            "weakComponents": len(component_sizes),
            "largestWeakComponentRatio": round(largest_component_ratio, 6),
            "surfaceDistanceCoverageRatio": round(surface_distance / max(total_distance, 1), 6),
            "roadClassDistanceRatios": road_class_ratios,
        },
        "probes": probe_report,
        "routes": route_report,
        "performance": {
            "decompressionSeconds": round(decompression_seconds, 6),
            "jsonParsingSeconds": round(parsing_seconds, 6),
            "indexingSeconds": round(indexing_seconds, 6),
            "probeRoutingSeconds": round(routing_seconds, 6),
            "totalAuditSeconds": round(time.perf_counter() - started_at, 6),
            "peakResidentMemoryMB": round(peak_resident_memory_mb, 3),
        },
    }


def atomic_write(path: Path, document: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def main() -> int:
    arguments = parse_args()
    try:
        region = load_region(arguments.regions, arguments.region_id)
        report = audit(arguments.graph, region)
    except (GraphAuditError, json.JSONDecodeError, OSError, KeyError, TypeError) as error:
        report = {
            "schemaVersion": 1,
            "regionID": arguments.region_id,
            "result": "failed",
            "error": str(error),
        }
        atomic_write(arguments.output, report)
        print(json.dumps(report, sort_keys=True), file=sys.stderr)
        return 1
    atomic_write(arguments.output, report)
    print(json.dumps(report, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
