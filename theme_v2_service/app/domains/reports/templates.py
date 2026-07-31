import json
import re
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator


SEMVER_RE = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"
)


class TemplateRegistryError(ValueError):
    pass


class TemplateNotFound(TemplateRegistryError):
    pass


class TemplateManifest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str = Field(pattern=r"^[a-z][a-z0-9_]*$")
    version: str
    base_family: Literal[
        "data_trend",
        "theme_synthesis",
        "professional_evaluation",
        "briefing_research",
    ]
    planner_description: str = Field(min_length=1)
    data_fit: list[str] = Field(min_length=1)
    analysis_method: str = Field(min_length=1)
    web_policy: Literal["none", "optional", "required", "authoritative_only"]
    illustration_policy: Literal["none", "optional", "required"]
    render_policy: str = Field(min_length=1)

    @field_validator("version")
    @classmethod
    def validate_semantic_version(cls, value: str) -> str:
        if SEMVER_RE.fullmatch(value) is None:
            raise ValueError("version must be a semantic version")
        return value

    @field_validator("data_fit")
    @classmethod
    def unique_data_fit(cls, value: list[str]) -> list[str]:
        if any(not item.strip() for item in value):
            raise ValueError("data_fit entries must be non-empty")
        if len(set(value)) != len(value):
            raise ValueError("data_fit entries must be unique")
        return value


@dataclass(frozen=True)
class TemplatePackage:
    manifest: TemplateManifest
    skill_markdown: str
    directory: Path


def _semver_key(value: str) -> tuple[int, int, int, int, str]:
    match = SEMVER_RE.fullmatch(value)
    if match is None:
        raise TemplateRegistryError(f"invalid semantic version: {value}")
    major, minor, patch, prerelease = match.groups()
    return (
        int(major),
        int(minor),
        int(patch),
        1 if prerelease is None else 0,
        prerelease or "",
    )


class TemplateRegistry:
    def __init__(self, packages: list[TemplatePackage]) -> None:
        self._packages = tuple(packages)
        self._index = {
            (package.manifest.id, package.manifest.version): package
            for package in packages
        }

    @classmethod
    def load(cls, root: Path) -> "TemplateRegistry":
        root = Path(root)
        packages: list[TemplatePackage] = []
        seen: set[tuple[str, str]] = set()
        for manifest_path in sorted(root.rglob("template.json")):
            skill_path = manifest_path.with_name("SKILL.md")
            if not skill_path.is_file():
                raise TemplateRegistryError(
                    f"missing SKILL.md next to {manifest_path}"
                )
            skill_markdown = skill_path.read_text(encoding="utf-8").strip()
            if not skill_markdown:
                raise TemplateRegistryError(f"empty SKILL.md: {skill_path}")
            try:
                raw = json.loads(manifest_path.read_text(encoding="utf-8"))
                manifest = TemplateManifest.model_validate(raw)
            except (OSError, json.JSONDecodeError, ValidationError) as exc:
                raise TemplateRegistryError(
                    f"invalid template manifest {manifest_path}: {exc}"
                ) from exc
            key = (manifest.id, manifest.version)
            if key in seen:
                raise TemplateRegistryError(
                    f"duplicate template package: {manifest.id}@{manifest.version}"
                )
            seen.add(key)
            packages.append(
                TemplatePackage(
                    manifest=manifest,
                    skill_markdown=skill_markdown,
                    directory=manifest_path.parent,
                )
            )
        if not packages:
            raise TemplateRegistryError(f"no template packages found under {root}")
        return cls(packages)

    @property
    def packages(self) -> tuple[TemplatePackage, ...]:
        return self._packages

    @property
    def template_ids(self) -> set[str]:
        return {package.manifest.id for package in self._packages}

    def get(
        self,
        template_id: str,
        version: str | None = None,
    ) -> TemplatePackage:
        if version is not None:
            try:
                return self._index[(template_id, version)]
            except KeyError as exc:
                raise TemplateNotFound(f"template not found: {template_id}@{version}") from exc
        matches = [
            package
            for package in self._packages
            if package.manifest.id == template_id
        ]
        if not matches:
            raise TemplateNotFound(f"template not found: {template_id}")
        return max(matches, key=lambda item: _semver_key(item.manifest.version))

    def candidates_for(self, capabilities: set[str]) -> list[TemplatePackage]:
        matches = [
            package
            for package in self._packages
            if capabilities.intersection(package.manifest.data_fit)
        ]
        return sorted(
            matches,
            key=lambda item: (
                item.manifest.id,
                tuple(-part for part in _semver_key(item.manifest.version)[:3]),
                -_semver_key(item.manifest.version)[3],
                _semver_key(item.manifest.version)[4],
            ),
        )


def repository_template_root() -> Path:
    return Path(__file__).resolve().parents[3] / "report-templates"


@lru_cache
def get_template_registry() -> TemplateRegistry:
    return TemplateRegistry.load(repository_template_root())
