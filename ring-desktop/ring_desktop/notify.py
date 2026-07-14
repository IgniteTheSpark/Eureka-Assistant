import argparse
import json
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from .vibration import VibrationType


DEFAULT_URL = "http://127.0.0.1:17863/vibrate"


def send_vibration(vibration_type: VibrationType, url: str = DEFAULT_URL):
    request = Request(
        url,
        data=json.dumps({"type": vibration_type.value}).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urlopen(request, timeout=3) as response:
        return json.loads(response.read())


def main():
    parser = argparse.ArgumentParser(
        description="Notify the connected BraveChip ring by vibration."
    )
    parser.add_argument(
        "--type",
        choices=[kind.value for kind in VibrationType],
        default=VibrationType.CONTINUOUS.value,
    )
    args = parser.parse_args()
    try:
        result = send_vibration(VibrationType(args.type))
    except HTTPError as error:
        detail = error.read().decode(errors="replace")
        parser.exit(1, f"ring notification failed ({error.code}): {detail}\n")
    except URLError as error:
        parser.exit(1, f"Ring-desktop is not running: {error.reason}\n")
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
