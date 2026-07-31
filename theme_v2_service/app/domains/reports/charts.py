import html
from dataclasses import dataclass, field
from statistics import fmean
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field


class ChartModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class ChartSeries(ChartModel):
    label: str = Field(min_length=1, max_length=100)
    source_paths: list[str] = Field(min_length=1, max_length=100)
    reducer: Literal["values", "count", "sum", "average"] = "values"


class ChartDirective(ChartModel):
    id: str = Field(pattern=r"^[A-Za-z0-9_-]+$")
    type: Literal["line", "bar", "summary"]
    title: str = Field(min_length=1, max_length=200)
    series: list[ChartSeries] = Field(min_length=1, max_length=8)


@dataclass(frozen=True)
class ChartRenderResult:
    svg: str | None
    warnings: list[str] = field(default_factory=list)


def _resolve_json_pointer(evidence: dict, pointer: str) -> Any:
    if not pointer.startswith("/user_evidence/"):
        raise KeyError(pointer)
    value: Any = evidence
    for raw_part in pointer.removeprefix("/").split("/"):
        part = raw_part.replace("~1", "/").replace("~0", "~")
        if isinstance(value, list):
            value = value[int(part)]
        elif isinstance(value, dict):
            value = value[part]
        else:
            raise KeyError(pointer)
    return value


def _series_values(series: ChartSeries, evidence: dict) -> list[float]:
    resolved = [_resolve_json_pointer(evidence, path) for path in series.source_paths]
    if series.reducer == "count":
        return [float(len(resolved))]
    if any(isinstance(value, bool) or not isinstance(value, (int, float)) for value in resolved):
        raise ValueError("non-numeric evidence source")
    numeric = [float(value) for value in resolved]
    if series.reducer == "sum":
        return [sum(numeric)]
    if series.reducer == "average":
        return [fmean(numeric)]
    return numeric


def _format_number(value: float) -> str:
    return f"{value:.6f}".rstrip("0").rstrip(".")


def render_chart(
    directive: ChartDirective,
    *,
    evidence: dict,
) -> ChartRenderResult:
    try:
        resolved = [
            (series, _series_values(series, evidence))
            for series in directive.series
        ]
    except (KeyError, IndexError, ValueError, TypeError):
        return ChartRenderResult(
            svg=None,
            warnings=["chart invalid: unavailable evidence source"],
        )
    all_values = [value for _, values in resolved for value in values]
    if not all_values:
        return ChartRenderResult(
            svg=None,
            warnings=["chart invalid: no numeric values"],
        )

    width, height = 720, 360
    plot_left, plot_top, plot_width, plot_height = 72, 64, 600, 230
    minimum, maximum = min(all_values), max(all_values)
    spread = maximum - minimum or 1.0
    colors = ("#46636B", "#B46C4D", "#7A8065", "#755D77")
    elements = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" '
        f'role="img" aria-labelledby="chart-{html.escape(directive.id)}-title">',
        f'<title id="chart-{html.escape(directive.id)}-title">{html.escape(directive.title)}</title>',
        '<rect width="720" height="360" rx="16" fill="#F7F5EF"/>',
        f'<text x="36" y="38" fill="#26383D" font-size="20">{html.escape(directive.title)}</text>',
    ]
    if directive.type == "summary":
        x = 52
        for index, (series, values) in enumerate(resolved):
            value = values[0]
            elements.extend(
                [
                    f'<text x="{x}" y="150" fill="{colors[index % len(colors)]}" font-size="44">{_format_number(value)}</text>',
                    f'<text x="{x}" y="185" fill="#53666C" font-size="15">{html.escape(series.label)}</text>',
                ]
            )
            x += 210
    else:
        elements.append(
            f'<line x1="{plot_left}" y1="{plot_top + plot_height}" '
            f'x2="{plot_left + plot_width}" y2="{plot_top + plot_height}" stroke="#B9C0BD"/>'
        )
        for series_index, (series, values) in enumerate(resolved):
            color = colors[series_index % len(colors)]
            step = plot_width / max(1, len(values))
            points = []
            for index, value in enumerate(values):
                x = plot_left + step * (index + 0.5)
                y = plot_top + plot_height - ((value - minimum) / spread * plot_height)
                points.append((x, y, value))
            if directive.type == "line":
                point_string = " ".join(f"{x:.2f},{y:.2f}" for x, y, _ in points)
                elements.append(
                    f'<polyline points="{point_string}" fill="none" stroke="{color}" stroke-width="3"/>'
                )
            for x, y, value in points:
                if directive.type == "bar":
                    bar_width = max(12.0, step * 0.5 / len(resolved))
                    elements.append(
                        f'<rect x="{x - bar_width / 2:.2f}" y="{y:.2f}" width="{bar_width:.2f}" '
                        f'height="{plot_top + plot_height - y:.2f}" rx="4" fill="{color}"/>'
                    )
                else:
                    elements.append(
                        f'<circle cx="{x:.2f}" cy="{y:.2f}" r="4" fill="{color}"/>'
                    )
                elements.append(
                    f'<text x="{x:.2f}" y="{max(14, y - 9):.2f}" text-anchor="middle" '
                    f'fill="#26383D" font-size="12">{_format_number(value)}</text>'
                )
            elements.append(
                f'<text x="{plot_left + series_index * 180}" y="334" fill="{color}" font-size="13">'
                f'{html.escape(series.label)}</text>'
            )
    elements.append("</svg>")
    return ChartRenderResult(svg="".join(elements))
