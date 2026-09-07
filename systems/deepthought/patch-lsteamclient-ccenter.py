import hashlib
import sys
from pathlib import Path
from struct import pack


EXPECTED_HASH = "9d68340151e999f68175feacb00b9fe5fab6fff062def58868c48b1d928f9c07"
HOOK = 0x137D9
# The executable .text raw mapping spans 0x1000..0x121000; this is zero padding.
CAVE = 0x120400
RETURN = 0x137A2
GET_MODULE_HANDLE_W = 0x258260
GET_PROC_ADDRESS = 0x258268


def rel32(next_instruction, target):
    return pack("<i", target - next_instruction)


target = Path(sys.argv[1])
data = bytearray(target.read_bytes())
if hashlib.sha256(data).hexdigest() != EXPECTED_HASH:
    raise RuntimeError("unsupported lsteamclient.dll")

original = bytes.fromhex(
    "0f b7 45 f4 66 23 42 10 0f 95 06 66 83 7a 10 00 "
    "ba 01 00 00 00 0f 95 46 01 eb b3 90 90"
)
if data[HOOK : HOOK + len(original)] != original or any(data[CAVE : CAVE + 0x98]):
    raise RuntimeError("unexpected lsteamclient.dll layout")

# Preserve every stock XInput action; only the zero-button CCenter entry jumps out.
hook = bytes.fromhex(
    "66 83 7a 10 00 "
    "74 11 "
    "0f b7 45 f4 "
    "66 23 42 10 "
    "0f 95 06 "
    "c6 46 01 01 "
    "eb"
) + pack("b", RETURN - (HOOK + 24)) + b"\xe9" + rel32(HOOK + 29, CAVE)

user32 = "user32.dll".encode("utf-16le") + b"\0\0"
get_async_key_state = b"GetAsyncKeyState\0"
user32_at = CAVE + 0x70
get_async_key_state_at = user32_at + len(user32)

cave = bytearray()
# The stock aligned 0x38-byte frame supplies Win64 shadow space; RETURN sets EDX=1.
cave += b"\x48\x8d\x0d" + rel32(CAVE + len(cave) + 7, user32_at)
cave += b"\xff\x15" + rel32(CAVE + len(cave) + 6, GET_MODULE_HANDLE_W)
cave += b"\x48\x85\xc0"
first_jz = len(cave)
cave += b"\x74\x00"
cave += b"\x48\x89\xc1"
cave += b"\x48\x8d\x15" + rel32(CAVE + len(cave) + 7, get_async_key_state_at)
cave += b"\xff\x15" + rel32(CAVE + len(cave) + 6, GET_PROC_ADDRESS)
cave += b"\x48\x85\xc0"
second_jz = len(cave)
cave += b"\x74\x00"
cave += b"\xb9\x87\x00\x00\x00"  # VK_F24
cave += b"\xff\xd0"
cave += b"\x25\x00\x80\x00\x00"
cave += b"\x0f\x95\x06"
cave += b"\xc6\x46\x01\x01"
cave += b"\xe9" + rel32(CAVE + len(cave) + 5, RETURN)
false_at = CAVE + len(cave)
cave += b"\x66\xc7\x06\x00\x01"
cave += b"\xe9" + rel32(CAVE + len(cave) + 5, RETURN)
cave[first_jz + 1] = false_at - (CAVE + first_jz + 2)
cave[second_jz + 1] = false_at - (CAVE + second_jz + 2)
cave += bytes(user32_at - (CAVE + len(cave)))
cave += user32 + get_async_key_state

data[HOOK : HOOK + len(hook)] = hook
data[CAVE : CAVE + len(cave)] = cave
target.write_bytes(data)
print(hashlib.sha256(data).hexdigest())
