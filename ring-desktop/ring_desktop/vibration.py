from enum import Enum
from typing import Union


class VibrationType(str, Enum):
    STRONG = "strong"
    CONTINUOUS = "continuous"
    GRADIENT = "gradient"


_TYPE_CODE = {
    VibrationType.STRONG: 0x01,
    VibrationType.CONTINUOUS: 0x02,
    VibrationType.GRADIENT: 0x03,
}


def build_immediate_frame(
    vibration_type: Union[VibrationType, str],
) -> bytes:
    """Build BraveChip's immediate linear-motor command.

    Frame format was verified against BCLRingSDK's command builder and on a
    physical BCL60392D5 ring: frameType, frameId, cmd, subCmd, UInt16LE type.
    """
    try:
        kind = VibrationType(vibration_type)
    except ValueError as error:
        raise ValueError(
            f"Unknown vibration type: {vibration_type}"
        ) from error
    return bytes((0x00, 0x00, 0x83, 0x04, _TYPE_CODE[kind], 0x00))
