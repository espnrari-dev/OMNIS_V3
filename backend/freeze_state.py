from pathlib import Path
import json
import os
import tempfile
import fcntl
from datetime import datetime, timezone

BASE = Path(__file__).resolve().parent.parent

FREEZE_FILE = (
    BASE
    / "data"
    / "freeze"
    / "OMNIS_V3_LOOP7_FREEZE.json"
)

RELEASE_FILE = (
    BASE
    / "data"
    / "freeze"
    / "OMNIS_V3_OPERATIONAL_RELEASE.json"
)

LOCK_FILE = (
    BASE
    / "data"
    / "freeze"
    / "OMNIS_V3_AUTHORITY.lock"
)


class ExecutionFrozenError(RuntimeError):
    pass


def _now():
    return datetime.now(timezone.utc).isoformat()


def _read_json(path):
    if not path.is_file():
        return None

    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def _atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)

    fd, tmp_name = tempfile.mkstemp(
        prefix=".omnis_authority_",
        dir=str(path.parent),
        text=True,
    )

    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(
                data,
                f,
                indent=2,
                sort_keys=True,
            )
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())

        os.replace(tmp_name, path)

        dir_fd = os.open(str(path.parent), os.O_RDONLY)

        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)

    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)


class _AuthorityLock:
    def __enter__(self):
        LOCK_FILE.parent.mkdir(
            parents=True,
            exist_ok=True,
        )

        self.fd = open(
            LOCK_FILE,
            "a+",
            encoding="utf-8",
        )

        fcntl.flock(
            self.fd.fileno(),
            fcntl.LOCK_EX,
        )

        return self

    def __exit__(self, exc_type, exc, tb):
        fcntl.flock(
            self.fd.fileno(),
            fcntl.LOCK_UN,
        )
        self.fd.close()


def get_freeze_state():
    state = _read_json(FREEZE_FILE)

    if state is None:
        return {
            "frozen": False,
            "reason": "freeze manifest missing",
        }

    release = _read_json(RELEASE_FILE)

    return {
        "frozen": state.get("frozen") is True,
        "schema": state.get("schema"),
        "freeze_reason": state.get("freeze_reason"),
        "frozen_at": state.get("frozen_at"),
        "terminal": state.get("terminal"),
        "loop_state": state.get("loop_state"),
        "continuation_policy": state.get(
            "continuation_policy"
        ),
        "freeze_sha256": state.get(
            "freeze_sha256"
        ),
        "operational_release": release,
    }


def _release_is_valid(state):
    release = state.get("operational_release")

    if not isinstance(release, dict):
        return False

    if release.get("schema") != (
        "OMNIS_V3_OPERATIONAL_RELEASE_V1"
    ):
        return False

    if release.get("authorized") is not True:
        return False

    if release.get("consumed") is True:
        return False

    if release.get("source_freeze_sha256") != (
        state.get("freeze_sha256")
    ):
        return False

    terminal = state.get("terminal") or {}

    if release.get("source_simulation_id") != (
        terminal.get("simulation_id")
    ):
        return False

    if release.get("seed") != (
        terminal.get("next_seed")
    ):
        return False

    if release.get("generations") != (
        terminal.get("generations")
    ):
        return False

    if bool(release.get("debt_allowed")) != bool(
        terminal.get("debt_allowed")
    ):
        return False

    return True


def execution_allowed():
    """
    Single authoritative execution decision.

    Unfrozen operational state:
        ALLOW

    Frozen state:
        BLOCK

    Frozen state + exact one-shot release:
        ALLOW
    """

    state = get_freeze_state()

    policy = state.get(
        "continuation_policy"
    ) or {}

    normal_allowed = (
        not state.get("frozen", False)
        and not policy.get(
            "execute_next_seed",
            False,
        )
    )

    if normal_allowed:
        return True

    return _release_is_valid(state)


def assert_execution_allowed():
    if not execution_allowed():
        state = get_freeze_state()

        raise ExecutionFrozenError(
            "OMNIS V3 execution blocked by freeze "
            f"authority: {json.dumps(state, sort_keys=True)}"
        )


def authorize_one_shot():
    """
    Authorize exactly one execution using the
    immutable Loop-7 terminal state.
    """

    with _AuthorityLock():
        state = get_freeze_state()

        if not state.get("frozen"):
            raise RuntimeError(
                "Cannot authorize execution: "
                "Loop-7 freeze is not active."
            )

        if _release_is_valid(state):
            raise RuntimeError(
                "An unconsumed operational release "
                "already exists."
            )

        terminal = state.get("terminal") or {}

        required = (
            "simulation_id",
            "next_seed",
            "generations",
            "debt_allowed",
        )

        missing = [
            key
            for key in required
            if key not in terminal
        ]

        if missing:
            raise RuntimeError(
                "Terminal state incomplete: "
                + ", ".join(missing)
            )

        release = {
            "schema":
                "OMNIS_V3_OPERATIONAL_RELEASE_V1",
            "authorized": True,
            "consumed": False,
            "authorized_at": _now(),
            "source_freeze_sha256":
                state.get("freeze_sha256"),
            "source_simulation_id":
                terminal["simulation_id"],
            "seed":
                int(terminal["next_seed"]),
            "generations":
                int(terminal["generations"]),
            "debt_allowed":
                bool(terminal["debt_allowed"]),
        }

        _atomic_write(
            RELEASE_FILE,
            release,
        )

        return release


def consume_execution_authority():
    """
    Atomically consume the one-shot release.

    The frozen base manifest is never modified.
    """

    with _AuthorityLock():
        state = get_freeze_state()

        if not _release_is_valid(state):
            raise ExecutionFrozenError(
                "No valid one-shot operational "
                "authority exists."
            )

        release = dict(
            state["operational_release"]
        )

        release["consumed"] = True
        release["consumed_at"] = _now()

        _atomic_write(
            RELEASE_FILE,
            release,
        )

        return release


def revoke_operational_release():
    with _AuthorityLock():
        if RELEASE_FILE.exists():
            RELEASE_FILE.unlink()

            dir_fd = os.open(
                str(RELEASE_FILE.parent),
                os.O_RDONLY,
            )

            try:
                os.fsync(dir_fd)
            finally:
                os.close(dir_fd)


def authority_status():
    state = get_freeze_state()

    return {
        "frozen": state.get("frozen"),
        "execution_allowed":
            execution_allowed(),
        "freeze_reason":
            state.get("freeze_reason"),
        "freeze_sha256":
            state.get("freeze_sha256"),
        "terminal":
            state.get("terminal"),
        "release":
            state.get("operational_release"),
    }
