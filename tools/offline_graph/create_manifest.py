#!/usr/bin/env python3
"""Create the canonical unsigned Memory Lanes offline-region manifest payload."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--regions", required=True, type=Path)
    parser.add_argument("--packs", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--generated-at", required=True)
    return parser.parse_args()


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            value.update(chunk)
    return value.hexdigest()


def main() -> None:
    arguments = parse_args()
    configuration = json.loads(arguments.regions.read_text(encoding="utf-8"))
    descriptors = []
    for region in sorted(configuration["regions"], key=lambda item: item["id"]):
        file_name = f"{region['id']}-v{region['version']}.mlgraph"
        pack = arguments.packs / file_name
        if not pack.is_file():
            raise FileNotFoundError(f"Missing built pack: {pack}")
        descriptors.append(
            {
                "id": region["id"],
                "name": region["name"],
                "detail": region["detail"],
                "bounds": region["bounds"],
                "version": region["version"],
                "formatVersion": region["formatVersion"],
                "encoding": region["encoding"],
                "byteCount": pack.stat().st_size,
                "sha256": digest(pack),
                "downloadPath": f"packs/{file_name}",
                "updatedAt": region["updatedAt"],
            }
        )
    manifest = {"schemaVersion": 1, "generatedAt": arguments.generated_at, "regions": descriptors}
    payload = json.dumps(manifest, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode("utf-8")
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = arguments.output.with_suffix(arguments.output.suffix + ".tmp")
    temporary.write_bytes(payload)
    os.replace(temporary, arguments.output)


if __name__ == "__main__":
    main()
