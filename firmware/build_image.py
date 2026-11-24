"""Reconstruct the hardware-tested image from the exact stock upgrade payload."""
import argparse
import hashlib
from pathlib import Path

STOCK = "210017e6d1879533612be6b2e950a8a106e8eee1fb3045f48c07cf8190358953"
RELEASE = "dea141e2c0dd1f1075b3c9bb856ed06fbc169b233cc5d55eedd180cc8e615420"


def build(stock, patch):
    # The older Mac updater embeds this payload verbatim. Verify every candidate.
    if len(stock) != 48640:
        header = bytes.fromhex("a78aa5806159a33eb454e93801bd0000")
        offset = stock.find(header)
        while offset >= 0:
            payload = stock[offset:offset + 48640]
            if hashlib.sha256(payload).hexdigest() == STOCK:
                stock = payload
                break
            offset = stock.find(header, offset + 1)
    if hashlib.sha256(stock).hexdigest() != STOCK:
        raise ValueError("Expected the original Kontrol F1 v11 upgrade payload.")
    if not patch.startswith(b"PATCH") or not patch.endswith(b"EOF"):
        raise ValueError("Invalid IPS header or trailer.")
    image = bytearray(stock)
    cursor = 5
    end = len(patch) - 3
    while cursor < end:
        if cursor + 5 > end:
            raise ValueError("Incomplete patch record.")
        start = int.from_bytes(patch[cursor:cursor + 3], "big")
        size = int.from_bytes(patch[cursor + 3:cursor + 5], "big")
        cursor += 5
        if not size or start + size > len(image) or cursor + size > end:
            raise ValueError("Invalid patch record.")
        image[start:start + size] = patch[cursor:cursor + size]
        cursor += size
    if hashlib.sha256(image).hexdigest() != RELEASE:
        raise ValueError("Reconstructed firmware checksum mismatch.")
    return image


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stock", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    patch = Path(__file__).with_name("F1-v11-midi-rgb.ips")
    image = build(args.stock.read_bytes(), patch.read_bytes())
    with args.output.open("xb") as output:
        output.write(image)
    print(RELEASE, args.output)
