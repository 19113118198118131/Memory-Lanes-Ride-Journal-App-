#!/usr/bin/env python3
"""Print one release configuration value for shell workflows."""

import argparse
import json
from pathlib import Path


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--regions", required=True, type=Path)
parser.add_argument("--region-id", required=True)
parser.add_argument("--value", required=True, choices=("bbox", "version", "updated-at", "source-url"))
arguments = parser.parse_args()
document = json.loads(arguments.regions.read_text(encoding="utf-8"))
region = next(item for item in document["regions"] if item["id"] == arguments.region_id)
if arguments.value == "bbox":
    bounds = region["bounds"]
    print(f"{bounds['west']},{bounds['south']},{bounds['east']},{bounds['north']}")
elif arguments.value == "version":
    print(region["version"])
elif arguments.value == "updated-at":
    print(region["updatedAt"])
else:
    print(document["source"]["url"])
