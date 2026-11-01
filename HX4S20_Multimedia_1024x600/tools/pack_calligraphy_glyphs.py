"""Losslessly pack the existing 1-bit title glyphs into two synchronous ROMs.

The original glyph file is a read-only reference. Each consecutive group of
16 source pixels becomes one dictionary word, with source bit j in word bit j.
The index ROM therefore uses glyph_address[14:4], and the final bit selector
uses the original glyph_address[3:0], delayed through both ROM reads.

Dictionary IDs are assigned in source first-occurrence order, never hash order.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pack(root: Path) -> dict:
    source = root / "rtl/calligraphy_glyphs.hex"
    index_path = root / "rtl/calligraphy_glyph_index.hex"
    dictionary_path = root / "rtl/calligraphy_glyph_dictionary.hex"
    report_path = root / "sim/calligraphy_packing_audit.json"
    original_hash = sha256(source)
    pixels = [int(token, 16) for token in source.read_text().split()]
    if len(pixels) != 32768 or any(value not in (0, 1) for value in pixels):
        raise ValueError("Expected exactly 32768 one-bit source pixels")

    dictionary: list[int] = []
    lookup: dict[int, int] = {}
    indices: list[int] = []
    for start in range(0, len(pixels), 16):
        word = sum(pixels[start + bit] << bit for bit in range(16))
        if word not in lookup:
            lookup[word] = len(dictionary)
            dictionary.append(word)
        indices.append(lookup[word])
    if len(dictionary) > 512:
        raise ValueError("Dictionary no longer fits its fixed 512 x 16 ROM")
    padded = dictionary + [0] * (512 - len(dictionary))
    index_path.write_text("".join(f"{value:03x}\n" for value in indices),
                          encoding="ascii", newline="\n")
    dictionary_path.write_text("".join(f"{word:04x}\n" for word in padded),
                               encoding="ascii", newline="\n")

    # Audit the saved files, rather than merely comparing in-memory objects.
    saved_indices = [int(token, 16) for token in index_path.read_text().split()]
    saved_dictionary = [int(token, 16)
                        for token in dictionary_path.read_text().split()]
    assert len(saved_indices) == 2048 and len(saved_dictionary) == 512
    assert all(0 <= value < len(dictionary) for value in saved_indices)
    decoded = [(saved_dictionary[saved_indices[address >> 4]] >> (address & 15)) & 1
               for address in range(32768)]
    mismatches = [address for address, (actual, expected) in
                  enumerate(zip(decoded, pixels)) if actual != expected]
    assert sha256(source) == original_hash, "Original glyph file changed"
    assert not mismatches, f"Glyph reconstruction differs at {mismatches[:8]}"
    report = {
        "format": "calligraphy-16bit-dictionary-v1",
        "source": "rtl/calligraphy_glyphs.hex",
        "source_sha256": original_hash,
        "source_bit_count": len(pixels),
        "source_bits_sha256": hashlib.sha256(bytes(pixels)).hexdigest(),
        "decoded_bits_sha256": hashlib.sha256(bytes(decoded)).hexdigest(),
        "source_packed_lsb_first_sha256": hashlib.sha256(bytes(
            sum(pixels[start + bit] << bit for bit in range(8))
            for start in range(0, len(pixels), 8))).hexdigest(),
        "index": "rtl/calligraphy_glyph_index.hex",
        "index_words": len(saved_indices),
        "index_word_bits": 9,
        "index_sha256": sha256(index_path),
        "dictionary": "rtl/calligraphy_glyph_dictionary.hex",
        "dictionary_words": len(saved_dictionary),
        "dictionary_word_bits": 16,
        "dictionary_sha256": sha256(dictionary_path),
        "unique_word_count": len(dictionary),
        "unused_dictionary_words": len(padded) - len(dictionary),
        "assignment_order": "source first occurrence",
        "word_bit_order": "word bit j equals source[block * 16 + j]",
        "decoded_bits_checked": len(decoded),
        "mismatches": len(mismatches),
        "first_mismatches": mismatches[:8],
        "original_source_unchanged": True,
        "logical_storage_bits_before": 32768,
        "logical_storage_bits_after": 2048 * 9 + 512 * 16,
        "expected_bram9k_before": 4,
        "expected_bram9k_after": 3,
        "physical_bram_count_requires_synthesis_confirmation": True,
    }
    report_path.write_text(json.dumps(report, indent=2) + "\n",
                           encoding="utf-8", newline="\n")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path,
                        default=Path(__file__).resolve().parents[1])
    result = pack(parser.parse_args().root.resolve())
    print(f"PASS {result['decoded_bits_checked']} decoded bits; "
          f"{result['unique_word_count']} unique words; "
          f"{result['mismatches']} mismatches; original unchanged")
