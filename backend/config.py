import os
import secrets
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR / "data"
MODELS_DIR = BASE_DIR / "models"
LOGS_DIR = BASE_DIR / "logs"

BLOOM_EXEC = "python3"
BLOOM_SCRIPT = str(Path.home() / "BLOOM" / "bloom_engine.py")

# FIX: bind to all interfaces by default so the dashboard is reachable from
# a browser on another device (e.g. phone browser hitting a Termux server).
# Override with OMNIS_HOST=127.0.0.1 if you only ever access it locally.
HOST = os.environ.get("OMNIS_HOST", "0.0.0.0")
PORT = int(os.environ.get("OMNIS_PORT", "5000"))

_KEY_FILE = DATA_DIR / ".api_key"

def _load_or_create_api_key() -> str:
    env_key = os.environ.get("OMNIS_API_KEY")
    if env_key:
        return env_key
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    if _KEY_FILE.exists():
        return _KEY_FILE.read_text().strip()
    key = secrets.token_urlsafe(32)
    _KEY_FILE.write_text(key)
    _KEY_FILE.chmod(0o600)
    return key

API_KEY = _load_or_create_api_key()

TELEMETRY_FILE = DATA_DIR / "latest.jsonl"

MAX_GENERATIONS = 50
MAX_SEED = 2**31 - 1

# ---------------------------------------------------------------------------
# VERITY SLM wiring
# ---------------------------------------------------------------------------
# FIX: the previous build pointed at a generic, never-populated
# models/slm_model.pt loaded with torch.load — it was never your trained
# model. Your actual model is VERITY, a GGUF checkpoint meant to run via
# llama.cpp. Point VERITY_MODEL_PATH at your real .gguf file:
#
#   export VERITY_MODEL_PATH=~/VERITY_fixed3.gguf
#
# If unset, the candidates below are searched in order and the first
# existing file is used. If none exist, the advisor logs a clear warning
# and falls back to a stub response instead of silently using the wrong
# model.
_env_model = os.environ.get("VERITY_MODEL_PATH")
_candidates = [
    _env_model,
    str(Path.home() / "VERITY_fixed3.gguf"),
    str(Path.home() / "VERITY.gguf"),
    str(Path.home() / "models" / "VERITY_fixed3.gguf"),
    str(MODELS_DIR / "VERITY_fixed3.gguf"),
    str(MODELS_DIR / "VERITY.gguf"),
]
VERITY_MODEL_PATH = next((Path(c) for c in _candidates if c and Path(c).exists()), None)

# llama.cpp generation settings — small, fast, since this is a 10M-param model.
VERITY_CTX_SIZE = int(os.environ.get("VERITY_CTX_SIZE", "512"))
VERITY_MAX_TOKENS = int(os.environ.get("VERITY_MAX_TOKENS", "80"))
VERITY_THREADS = int(os.environ.get("VERITY_THREADS", str(os.cpu_count() or 4)))
