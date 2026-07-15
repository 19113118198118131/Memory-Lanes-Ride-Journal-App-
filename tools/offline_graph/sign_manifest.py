#!/usr/bin/env python3
"""Sign a canonical manifest payload with an Ed25519 release key."""

from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import tempfile
from pathlib import Path


PKCS8_ED25519_PREFIX = bytes.fromhex("302e020100300506032b657004220420")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--payload", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--expected-public-key", required=True)
    return parser.parse_args()


def main() -> None:
    arguments = parse_args()
    encoded_key = os.environ.get("OFFLINE_MANIFEST_SIGNING_KEY", "")
    try:
        private_key = base64.b64decode(encoded_key, validate=True)
    except ValueError as error:
        raise ValueError("OFFLINE_MANIFEST_SIGNING_KEY is not valid base64") from error
    if len(private_key) != 32:
        raise ValueError("OFFLINE_MANIFEST_SIGNING_KEY must contain a 32-byte Ed25519 private key")

    payload = arguments.payload.read_bytes()
    with tempfile.TemporaryDirectory() as temporary_directory:
        directory = Path(temporary_directory)
        key_path = directory / "key.der"
        signature_path = directory / "signature.bin"
        public_path = directory / "public.der"
        key_path.write_bytes(PKCS8_ED25519_PREFIX + private_key)
        subprocess.run(
            ["openssl", "pkeyutl", "-sign", "-rawin", "-inkey", str(key_path), "-keyform", "DER", "-in", str(arguments.payload), "-out", str(signature_path)],
            check=True,
        )
        subprocess.run(
            ["openssl", "pkey", "-in", str(key_path), "-inform", "DER", "-pubout", "-outform", "DER", "-out", str(public_path)],
            check=True,
        )
        public_der = public_path.read_bytes()
        actual_public_key = base64.b64encode(public_der[-32:]).decode("ascii")
        if actual_public_key != arguments.expected_public_key:
            raise ValueError("Signing key does not match the public key pinned in the iOS app")
        signature = signature_path.read_bytes()

    envelope = {
        "schemaVersion": 1,
        "keyID": arguments.key_id,
        "payload": base64.b64encode(payload).decode("ascii"),
        "signature": base64.b64encode(signature).decode("ascii"),
    }
    output = json.dumps(envelope, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode("utf-8")
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = arguments.output.with_suffix(arguments.output.suffix + ".tmp")
    temporary.write_bytes(output)
    os.replace(temporary, arguments.output)


if __name__ == "__main__":
    main()
