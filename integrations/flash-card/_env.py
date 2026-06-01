"""
_env — load `flash-card.env` so the bridge scripts pick up host config.

FlashType invokes `eureka-bridge.py` directly as its external-ASR command, so
that process never sees the env the shell scripts export. listen-watcher.py is
usually run via start.sh (which does source the env), but it may also be run
bare. Either way, both scripts call `load_env_file()` at startup to read
KEY=VALUE lines from `flash-card.env` sitting next to them.

No external dependency (python-dotenv not assumed). Values already present in
the real environment win — `os.environ.setdefault`, never override — so the
shell can still take precedence when it does export.
"""
import os


def load_env_file(script_file: str) -> None:
    """Load `flash-card.env` from the directory holding `script_file`.

    Pass `__file__` from the caller. Missing file is a silent no-op (the
    defaults baked into each script keep working). `~` and `$VAR` in values
    are expanded so paths like `$HOME/.flash-type/...` resolve.
    """
    here = os.path.dirname(os.path.abspath(script_file))
    path = os.path.join(here, "flash-card.env")
    try:
        with open(path, "r", encoding="utf-8") as f:
            for raw in f:
                line = raw.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, _, val = line.partition("=")
                key = key.strip()
                if not key:
                    continue
                val = val.strip().strip('"').strip("'")
                val = os.path.expanduser(os.path.expandvars(val))
                os.environ.setdefault(key, val)
    except FileNotFoundError:
        pass
