from dataclasses import dataclass
from typing import Literal


ColorScheme = Literal["light", "dark"]


@dataclass(frozen=True)
class StyleVariant:
    surface: str
    palette: str
    color_scheme: ColorScheme


FAMILY_VARIANTS: dict[str, tuple[StyleVariant, StyleVariant]] = {
    "data_trend": (
        StyleVariant("surface-dashboard", "pal-dashboard", "dark"),
        StyleVariant("surface-neon", "pal-neon", "dark"),
    ),
    "theme_synthesis": (
        StyleVariant("surface-editorial", "pal-ink", "dark"),
        StyleVariant("surface-note", "pal-warm", "light"),
    ),
    "professional_evaluation": (
        StyleVariant("surface-deck", "pal-minimal", "light"),
        StyleVariant("surface-forest2", "pal-forest", "dark"),
    ),
    "briefing_research": (
        StyleVariant("surface-mag", "pal-warm", "light"),
        StyleVariant("surface-wdash", "pal-dashboard", "dark"),
    ),
}


def select_variant(base_family: str, seed: int) -> tuple[StyleVariant, bool]:
    variants = FAMILY_VARIANTS.get(base_family)
    if variants is None:
        return FAMILY_VARIANTS["briefing_research"][0], True
    return variants[seed % 2], False
