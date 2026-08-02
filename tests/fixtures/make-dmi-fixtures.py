#!/usr/bin/env python3
"""Build synthetic SMBIOS type-17 records for the DMI parser tests.

The real structures live under /sys/firmware/dmi/entries/17-*/raw at mode 0400, so the
parser cannot be exercised against this machine without root — and testing against one
machine's memory would prove very little anyway. These fixtures encode the cases that
actually differ: the megabyte and kilobyte size units, the 0x7FFF escape to the 32-bit
extended size, an empty slot, and a stick whose configured speed is below its rated one.

Offsets are SMBIOS 3.x section 7.18. Regenerate with:

    python3 tests/fixtures/make-dmi-fixtures.py
"""
import pathlib
import struct

HERE = pathlib.Path(__file__).parent


def type17(
    *,
    size_field,
    extended_size=0,
    mem_type=0x22,
    form_factor=0x0D,
    speed=5600,
    configured_speed=5200,
    strings,
    locator_idx=1,
    bank_idx=2,
    manufacturer_idx=3,
    serial_idx=4,
    asset_idx=5,
    part_idx=6,
):
    """One Memory Device structure: formatted area, then the NUL-separated string set."""
    body = bytearray(0x54)
    body[0x00] = 17  # Type: Memory Device
    body[0x01] = 0x54  # Length of the formatted area
    struct.pack_into("<H", body, 0x02, 0x1100)  # Handle
    struct.pack_into("<H", body, 0x04, 0x1000)  # Physical Memory Array handle
    struct.pack_into("<H", body, 0x06, 0xFFFE)  # Memory Error Info handle
    struct.pack_into("<H", body, 0x08, 64)  # Total width
    struct.pack_into("<H", body, 0x0A, 64)  # Data width
    struct.pack_into("<H", body, 0x0C, size_field)
    body[0x0E] = form_factor
    body[0x0F] = 0  # Device set
    body[0x10] = locator_idx
    body[0x11] = bank_idx
    body[0x12] = mem_type
    struct.pack_into("<H", body, 0x13, 0x0080)  # Type detail: synchronous
    struct.pack_into("<H", body, 0x15, speed)
    body[0x17] = manufacturer_idx
    body[0x18] = serial_idx
    body[0x19] = asset_idx
    body[0x1A] = part_idx
    body[0x1B] = 0
    struct.pack_into("<I", body, 0x1C, extended_size)
    struct.pack_into("<H", body, 0x20, configured_speed)

    if strings:
        tail = b"".join(s.encode() + b"\0" for s in strings) + b"\0"
    else:
        tail = b"\0\0"  # No strings at all is still a terminated set.
    return bytes(body) + tail


CASES = {
    # A laptop SODIMM: 16 GiB DDR5, running below its rated speed.
    "17-0": type17(
        size_field=16384,
        strings=["DIMM 0", "BANK 0", "SK Hynix", "SERIAL-DO-NOT-PRINT", "No Asset Tag",
                 "HMCG78AGBSA095N"],
    ),
    # Desktop DIMM, 32 GiB via the 0x7FFF escape to Extended Size, at rated speed.
    "17-1": type17(
        size_field=0x7FFF,
        extended_size=32768,
        form_factor=0x09,
        mem_type=0x1A,
        speed=3200,
        configured_speed=3200,
        strings=["DIMM_A1", "BANK 0", "Corsair", "SER2", "No Asset Tag", "CMK32GX4M2"],
    ),
    # An empty slot: size 0. Must be skipped, not printed as "0 GiB".
    "17-2": type17(size_field=0, strings=["DIMM_A2", "BANK 1"], manufacturer_idx=0,
                   part_idx=0, serial_idx=0, asset_idx=0),
    # Bit 15 set means the low 15 bits are kilobytes, not megabytes — so the unit only
    # reaches 32 MB. 16384 KB is 16 MB, and misreading the flag would report it as
    # 16 GB, which is the whole reason this case is here.
    "17-3": type17(
        size_field=0x8000 | 16384,
        mem_type=0x18,
        form_factor=0x09,
        speed=1600,
        configured_speed=1600,
        strings=["DIMM_B1", "BANK 2", "Micron", "SER3", "No Asset Tag", "MT8JTF"],
    ),
    # Firmware that knows nothing: unknown size must be skipped rather than guessed.
    "17-4": type17(size_field=0xFFFF, strings=["DIMM_B2", "BANK 3"],
                   manufacturer_idx=0, part_idx=0, serial_idx=0, asset_idx=0),
    # Populated stick with no manufacturer or part number recorded.
    "17-5": type17(
        size_field=8192,
        mem_type=0x22,
        strings=["DIMM 1", "BANK 1", "Unknown", "SER5", "Not Specified", "Not Specified"],
    ),
}

for name, blob in CASES.items():
    d = HERE / "dmi-entries" / name
    d.mkdir(parents=True, exist_ok=True)
    (d / "raw").write_bytes(blob)
    print(f"{name}/raw  {len(blob)} bytes")
