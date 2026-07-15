#!/usr/bin/env python3
"""Verify a signed manifest envelope using the iOS-pinned Ed25519 public key."""

from __future__ import annotations

import argparse
import base64
import json
import subprocess
import tempfile
from pathlib import Path


SPKI_ED25519_PREFIX = bytes.fromhex("302a300506032b6570032100")


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--manifest", required=True, type=Path)
parser.add_argument("--public-key", required=True)
arguments = parser.parse_args()

envelope = json.loads(arguments.manifest.read_text(encoding="utf-8"))
if envelope.get("schemaVersion") != 1:
    raise ValueError("Unsupported signed-envelope version")
public_key = base64.b64decode(arguments.public_key, validate=True)
payload = base64.b64decode(envelope["payload"], validate=True)
signature = base64.b64decode(envelope["signature"], validate=True)
if len(public_key) != 32 or len(signature) != 64:
    raise ValueError("Invalid Ed25519 key or signature length")

with tempfile.TemporaryDirectory() as temporary_directory:
    directory = Path(temporary_directory)
    public_path = directory / "public.der"
    payload_path = directory / "payload.json"
    signature_path = directory / "signature.bin"
    public_path.write_bytes(SPKI_ED25519_PREFIX + public_key)
    payload_path.write_bytes(payload)
    signature_path.write_bytes(signature)
    subprocess.run(
        [
            "openssl",
            "pkeyutl",
            "-verify",
            "-rawin",
            "-pubin",
            "-inkey",
            str(public_path),
            "-keyform",
            "DER",
            "-in",
            str(payload_path),
            "-sigfile",
            str(signature_path),
        ],
        check=True,
    )

manifest = json.loads(payload)
if manifest.get("schemaVersion") != 1 or not manifest.get("regions"):
    raise ValueError("Signed payload is not a valid offline-region manifest")
print(json.dumps({"regions": len(manifest["regions"]), "generatedAt": manifest["generatedAt"]}, sort_keys=True))
