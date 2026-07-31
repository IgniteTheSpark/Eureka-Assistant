import pytest

from app.jobs.registry import JobHandlerRegistry


async def _handler(job):
    return None


def test_registry_resolves_registered_handler():
    registry = JobHandlerRegistry()

    registry.register("probe", _handler)

    assert registry.resolve("probe") is _handler


def test_registry_rejects_duplicate_registration():
    registry = JobHandlerRegistry()
    registry.register("probe", _handler)

    with pytest.raises(ValueError, match="already registered"):
        registry.register("probe", _handler)


def test_registry_rejects_unknown_job_type():
    registry = JobHandlerRegistry()

    with pytest.raises(KeyError, match="unknown job type"):
        registry.resolve("missing")
