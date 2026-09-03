"""
Compatibility facade.

The actual execution authority lives exclusively in
backend.freeze_state.
"""

from .freeze_state import (
    authorize_one_shot,
    consume_execution_authority,
    execution_allowed,
    get_freeze_state,
    revoke_operational_release,
    authority_status,
)


def execution_authorized():
    return execution_allowed()


def status():
    return authority_status()


def release_one(seed=None, generations=None, debt_allowed=None):
    """
    Return the existing valid one-shot release.

    If no release exists, create exactly one using the
    immutable Loop-7 terminal state.

    Never create a second unconsumed release.
    """
    state = get_freeze_state()
    terminal = state.get("terminal") or {}
    existing = state.get("operational_release")

    expected_seed = terminal.get("next_seed")
    expected_generations = terminal.get("generations")
    expected_debt = terminal.get("debt_allowed")

    if seed is not None and int(seed) != int(expected_seed):
        raise RuntimeError(
            f"Seed mismatch: requested={seed}, expected={expected_seed}"
        )

    if generations is not None and int(generations) != int(expected_generations):
        raise RuntimeError(
            f"Generation mismatch: requested={generations}, "
            f"expected={expected_generations}"
        )

    if debt_allowed is not None and bool(debt_allowed) != bool(expected_debt):
        raise RuntimeError(
            f"Debt policy mismatch: requested={debt_allowed}, "
            f"expected={expected_debt}"
        )

    if existing is not None:
        if existing.get("consumed") is True:
            raise RuntimeError(
                "Operational release already consumed."
            )

        if not execution_allowed():
            raise RuntimeError(
                "Existing operational release is invalid."
            )

        return existing

    return authorize_one_shot()

