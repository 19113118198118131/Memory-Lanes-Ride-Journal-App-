#!/usr/bin/env python3
"""Compile an Osmium-extracted OSM XML file into a Memory Lanes road graph."""

from __future__ import annotations

import argparse
import json
import math
import os
import zlib
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path


ROAD_CLASSES = {
    "motorway": "motorway",
    "motorway_link": "motorway",
    "trunk": "trunk",
    "trunk_link": "trunk",
    "primary": "primary",
    "primary_link": "primary",
    "secondary": "secondary",
    "secondary_link": "secondary",
    "tertiary": "tertiary",
    "tertiary_link": "tertiary",
    "residential": "residential",
    "living_street": "residential",
    "unclassified": "unclassified",
    "road": "unclassified",
    "service": "service",
}

DEFAULT_SPEED_KPH = {
    "motorway": 100.0,
    "trunk": 90.0,
    "primary": 80.0,
    "secondary": 70.0,
    "tertiary": 60.0,
    "residential": 40.0,
    "unclassified": 50.0,
    "service": 25.0,
}

DENIED_ACCESS = {"no", "private", "agricultural", "forestry", "customers"}
ALLOWED_ACCESS = {"yes", "designated", "permissive", "destination"}
ONEWAY_FORWARD = {"yes", "true", "1"}
ONEWAY_REVERSE = {"-1", "reverse"}


@dataclass(frozen=True)
class Bounds:
    south: float
    west: float
    north: float
    east: float

    def contains(self, latitude: float, longitude: float) -> bool:
        return self.south <= latitude <= self.north and self.west <= longitude <= self.east


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path, help="Reference-complete OSM XML")
    parser.add_argument("--regions", required=True, type=Path, help="Region configuration JSON")
    parser.add_argument("--region-id", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--generated-at", required=True, help="ISO-8601 release timestamp")
    return parser.parse_args()


def load_region(path: Path, region_id: str) -> dict:
    document = json.loads(path.read_text(encoding="utf-8"))
    if document.get("schemaVersion") != 1:
        raise ValueError("Unsupported region configuration")
    matches = [region for region in document.get("regions", []) if region.get("id") == region_id]
    if len(matches) != 1:
        raise ValueError(f"Expected exactly one region named {region_id!r}")
    region = matches[0]
    if region.get("formatVersion") != 1 or region.get("encoding") != "zlib-json":
        raise ValueError("Region does not use the supported graph format")
    return region


def tags(element: ET.Element) -> dict[str, str]:
    return {
        child.attrib["k"]: child.attrib["v"]
        for child in element
        if child.tag == "tag" and "k" in child.attrib and "v" in child.attrib
    }


def motorcycle_is_allowed(values: dict[str, str]) -> bool:
    if values.get("area") == "yes" or values.get("highway") not in ROAD_CLASSES:
        return False
    motorcycle = values.get("motorcycle")
    motor_vehicle = values.get("motor_vehicle")
    general = values.get("access")
    if motorcycle in DENIED_ACCESS:
        return False
    if motorcycle in ALLOWED_ACCESS:
        return True
    if motor_vehicle in DENIED_ACCESS:
        return False
    if motor_vehicle in ALLOWED_ACCESS:
        return True
    return general not in DENIED_ACCESS


def parse_speed_kph(raw: str | None, road_class: str) -> float:
    if raw:
        first = raw.split(";")[0].strip().lower()
        numeric = "".join(character for character in first if character.isdigit() or character == ".")
        if numeric:
            value = float(numeric)
            if "mph" in first:
                value *= 1.609344
            if 5.0 <= value <= 160.0:
                return round(value, 3)
    return DEFAULT_SPEED_KPH[road_class]


def haversine_meters(first: tuple[float, float], second: tuple[float, float]) -> float:
    latitude1, longitude1 = map(math.radians, first)
    latitude2, longitude2 = map(math.radians, second)
    latitude_delta = latitude2 - latitude1
    longitude_delta = longitude2 - longitude1
    value = (
        math.sin(latitude_delta / 2) ** 2
        + math.cos(latitude1) * math.cos(latitude2) * math.sin(longitude_delta / 2) ** 2
    )
    return 6_371_008.8 * 2 * math.atan2(math.sqrt(value), math.sqrt(1 - value))


def edge(
    way_id: int,
    source: int,
    destination: int,
    distance: float,
    speed_kph: float,
    road_class: str,
    values: dict[str, str],
) -> dict:
    return {
        "wayID": way_id,
        "sourceNodeID": source,
        "destinationNodeID": destination,
        "distanceMeters": round(distance, 3),
        "expectedTravelTime": round(distance / (speed_kph / 3.6), 3),
        "roadClass": road_class,
        "name": values.get("name"),
        "surface": values.get("surface"),
        "maximumSpeedKPH": speed_kph if values.get("maxspeed") else None,
    }


def relation_restriction(element: ET.Element, retained_way_ids: set[int]) -> dict | None:
    values = tags(element)
    source_tag = values.get("restriction:motorcycle") or values.get("restriction")
    conditional = values.get("restriction:motorcycle:conditional") or values.get("restriction:conditional")
    condition = None
    if not source_tag and conditional:
        components = conditional.split("@", 1)
        source_tag = components[0].strip()
        condition = components[1].strip() if len(components) == 2 else conditional
    if values.get("type") != "restriction" or not source_tag:
        return None
    if values.get("except") and "motorcycle" in values["except"].split(";"):
        return None

    from_way = None
    to_way = None
    via_node = None
    via_ways: list[int] = []
    for member in element:
        if member.tag != "member":
            continue
        role = member.attrib.get("role")
        member_type = member.attrib.get("type")
        reference = member.attrib.get("ref")
        if not reference:
            continue
        if role == "from" and member_type == "way":
            from_way = int(reference)
        elif role == "to" and member_type == "way":
            to_way = int(reference)
        elif role == "via" and member_type == "node":
            via_node = int(reference)
        elif role == "via" and member_type == "way":
            via_ways.append(int(reference))

    if not from_way or not to_way or (not via_node and not via_ways):
        return None
    if any(way_id not in retained_way_ids for way_id in [from_way, to_way, *via_ways]):
        return None
    return {
        "fromWayID": from_way,
        "viaNodeID": via_node,
        "viaWayIDs": via_ways,
        "toWayID": to_way,
        "kind": "only" if source_tag.startswith("only_") else "prohibited",
        "sourceTag": source_tag,
        "condition": condition,
    }


def compile_graph(input_path: Path, region: dict, generated_at: str) -> dict:
    bounds = Bounds(**region["bounds"])
    coordinates: dict[int, tuple[float, float]] = {}
    used_node_ids: set[int] = set()
    retained_way_ids: set[int] = set()
    graph_edges: list[dict] = []
    restrictions: list[dict] = []

    for _, element in ET.iterparse(input_path, events=("end",)):
        if element.tag == "node":
            coordinates[int(element.attrib["id"])] = (
                float(element.attrib["lat"]),
                float(element.attrib["lon"]),
            )
        elif element.tag == "way":
            values = tags(element)
            if motorcycle_is_allowed(values):
                node_ids = [
                    int(child.attrib["ref"])
                    for child in element
                    if child.tag == "nd" and "ref" in child.attrib
                ]
                road_class = ROAD_CLASSES[values["highway"]]
                speed_kph = parse_speed_kph(values.get("maxspeed"), road_class)
                oneway = values.get("oneway", "").lower()
                is_roundabout = values.get("junction") == "roundabout"
                way_edges = 0
                for first_id, second_id in zip(node_ids, node_ids[1:]):
                    first = coordinates.get(first_id)
                    second = coordinates.get(second_id)
                    if not first or not second or not (bounds.contains(*first) or bounds.contains(*second)):
                        continue
                    distance = haversine_meters(first, second)
                    if distance <= 0.01:
                        continue
                    if oneway in ONEWAY_REVERSE:
                        graph_edges.append(edge(int(element.attrib["id"]), second_id, first_id, distance, speed_kph, road_class, values))
                    else:
                        graph_edges.append(edge(int(element.attrib["id"]), first_id, second_id, distance, speed_kph, road_class, values))
                        if oneway not in ONEWAY_FORWARD and not is_roundabout:
                            graph_edges.append(edge(int(element.attrib["id"]), second_id, first_id, distance, speed_kph, road_class, values))
                    used_node_ids.update((first_id, second_id))
                    way_edges += 1
                if way_edges:
                    retained_way_ids.add(int(element.attrib["id"]))
        elif element.tag == "relation":
            restriction = relation_restriction(element, retained_way_ids)
            if restriction:
                restrictions.append(restriction)
        if element.tag in {"node", "way", "relation"}:
            element.clear()

    if not graph_edges:
        raise ValueError("No motorcycle-routable road edges were produced")
    missing_nodes = used_node_ids.difference(coordinates)
    if missing_nodes:
        raise ValueError(f"Missing {len(missing_nodes)} referenced nodes")

    nodes = [
        {
            "id": node_id,
            "coordinate": {
                "latitude": coordinates[node_id][0],
                "longitude": coordinates[node_id][1],
            },
        }
        for node_id in sorted(used_node_ids)
    ]
    graph_edges.sort(key=lambda item: (item["sourceNodeID"], item["destinationNodeID"], item["wayID"]))
    restrictions.sort(key=lambda item: (item["viaNodeID"] or 0, item["viaWayIDs"], item["fromWayID"], item["toWayID"]))
    return {
        "formatVersion": region["formatVersion"],
        "regionID": region["id"],
        "generatedAt": generated_at,
        "bounds": region["bounds"],
        "attribution": "© OpenStreetMap contributors, ODbL 1.0",
        "nodes": nodes,
        "edges": graph_edges,
        "turnRestrictions": restrictions,
    }


def deterministic_zlib(payload: bytes) -> bytes:
    return zlib.compress(payload, level=9)


def atomic_write(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_bytes(payload)
    os.replace(temporary, path)


def main() -> None:
    arguments = parse_args()
    region = load_region(arguments.regions, arguments.region_id)
    graph = compile_graph(arguments.input, region, arguments.generated_at)
    payload = json.dumps(graph, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode("utf-8")
    atomic_write(arguments.output, deterministic_zlib(payload))
    print(
        json.dumps(
            {
                "regionID": region["id"],
                "nodes": len(graph["nodes"]),
                "edges": len(graph["edges"]),
                "turnRestrictions": len(graph["turnRestrictions"]),
                "bytes": arguments.output.stat().st_size,
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
