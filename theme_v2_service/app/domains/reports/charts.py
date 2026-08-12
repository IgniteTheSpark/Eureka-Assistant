import html
import hashlib
from dataclasses import dataclass, field
from statistics import fmean
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field


class ChartModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class ChartSeries(ChartModel):
    label: str = Field(min_length=1, max_length=100)
    labels: list[str] = Field(default_factory=list, max_length=100)
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


@dataclass(frozen=True)
class ValidatedCharts:
    svgs: dict[str, str] = field(default_factory=dict)
    warnings: list[str] = field(default_factory=list)


def _resolve_json_pointer(evidence: dict, pointer: str) -> Any:
    if not pointer.startswith(("/user_evidence/", "/derived_metrics/")):
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


def _pointer_part(value: str) -> str:
    return value.replace("~", "~0").replace("/", "~1")


def _stable_chart_id(*parts: str) -> str:
    digest = hashlib.sha256("\0".join(parts).encode("utf-8")).hexdigest()[:16]
    return f"chart-{digest}"


def _chart_copy(
    *,
    template_id: str | None,
    dimension_name: str,
    numeric_name: str,
) -> tuple[str, str]:
    if template_id == "finance_review" and str(numeric_name).casefold().endswith(
        "amount"
    ):
        dimension_title = (
            "每日支出"
            if dimension_name in {"effective_date", "date"}
            else "支出构成"
        )
        return dimension_title, "支出"
    return f"{numeric_name} 按 {dimension_name} 变化", str(numeric_name)


def build_default_chart_directives(
    evidence: dict,
    *,
    template_id: str | None = None,
) -> list[ChartDirective]:
    """Create one deterministic chart from server-derived metrics."""
    metrics = evidence.get("derived_metrics")
    if not isinstance(metrics, dict):
        return []
    grouped = metrics.get("grouped_fields")
    if isinstance(grouped, dict):
        dimension_names = sorted(
            grouped,
            key=lambda name: (
                name not in {"effective_date", "date"},
                str(name),
            ),
        )
        for dimension_name in dimension_names:
            groups = grouped.get(dimension_name)
            if not isinstance(groups, dict) or len(groups) < 2:
                continue
            numeric_names = sorted(
                {
                    numeric_name
                    for group in groups.values()
                    if isinstance(group, dict)
                    for numeric_name in (
                        group.get("numeric_fields", {}).keys()
                        if isinstance(group.get("numeric_fields"), dict)
                        else []
                    )
                },
                key=lambda name: (
                    not str(name).casefold().endswith("amount"),
                    str(name),
                ),
            )
            for numeric_name in numeric_names:
                labels: list[str] = []
                paths: list[str] = []
                for label, group in sorted(groups.items()):
                    numeric_fields = (
                        group.get("numeric_fields")
                        if isinstance(group, dict)
                        else None
                    )
                    stats = (
                        numeric_fields.get(numeric_name)
                        if isinstance(numeric_fields, dict)
                        else None
                    )
                    if not isinstance(stats, dict) or not isinstance(
                        stats.get("sum"), (int, float)
                    ):
                        continue
                    labels.append(str(label))
                    paths.append(
                        "/derived_metrics/grouped_fields/"
                        f"{_pointer_part(str(dimension_name))}/"
                        f"{_pointer_part(str(label))}/numeric_fields/"
                        f"{_pointer_part(str(numeric_name))}/sum"
                    )
                if len(paths) < 2:
                    continue
                title, series_label = _chart_copy(
                    template_id=template_id,
                    dimension_name=str(dimension_name),
                    numeric_name=str(numeric_name),
                )
                return [
                    ChartDirective(
                        id=(
                            f"{dimension_name}-{numeric_name}-trend".replace(
                                ".", "-"
                            )
                            if all(
                                str(part).replace("_", "").isalnum()
                                and str(part).isascii()
                                for part in (dimension_name, numeric_name)
                            )
                            else _stable_chart_id(
                                str(dimension_name),
                                str(numeric_name),
                                "trend",
                            )
                        ),
                        type=(
                            "line"
                            if dimension_name in {"effective_date", "date"}
                            else "bar"
                        ),
                        title=title,
                        series=[
                            ChartSeries(
                                label=series_label,
                                labels=labels,
                                source_paths=paths,
                            )
                        ],
                    )
                ]

    fields = metrics.get("fields")
    if isinstance(fields, dict):
        for name, stats in sorted(fields.items()):
            if not isinstance(stats, dict) or not isinstance(
                stats.get("sum"), (int, float)
            ):
                continue
            return [
                ChartDirective(
                    id=(
                        f"{name}-summary".replace(".", "-")
                        if str(name).replace("_", "").isalnum()
                        and str(name).isascii()
                        else _stable_chart_id(str(name), "summary")
                    ),
                    type="summary",
                    title=f"{name} 汇总",
                    series=[
                        ChartSeries(
                            label=str(name),
                            source_paths=[
                                f"/derived_metrics/fields/{_pointer_part(str(name))}/sum"
                            ],
                        )
                    ],
                )
            ]
    return []


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
    minimum, maximum = min(0.0, min(all_values)), max(0.0, max(all_values))
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
            for point_index, (x, y, value) in enumerate(points):
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
                if point_index < len(series.labels):
                    elements.append(
                        f'<text x="{x:.2f}" y="{plot_top + plot_height + 18}" '
                        f'text-anchor="middle" fill="#53666C" font-size="11">'
                        f'{html.escape(series.labels[point_index])}</text>'
                    )
            elements.append(
                f'<text x="{plot_left + series_index * 180}" y="334" fill="{color}" font-size="13">'
                f'{html.escape(series.label)}</text>'
            )
    elements.append("</svg>")
    return ChartRenderResult(svg="".join(elements))


def render_validated_charts(
    raw_directives: list[ChartDirective | dict],
    *,
    evidence: dict,
    include_default: bool,
    template_id: str | None = None,
) -> ValidatedCharts:
    svgs: dict[str, str] = {}
    warnings: list[str] = []
    for raw in raw_directives:
        try:
            directive = ChartDirective.model_validate(raw)
        except (TypeError, ValueError):
            warnings.append("chart invalid: malformed directive")
            continue
        rendered = render_chart(directive, evidence=evidence)
        warnings.extend(rendered.warnings)
        if rendered.svg is not None:
            svgs[directive.id] = rendered.svg
    if include_default and not svgs:
        for directive in build_default_chart_directives(
            evidence,
            template_id=template_id,
        ):
            rendered = render_chart(directive, evidence=evidence)
            warnings.extend(rendered.warnings)
            if rendered.svg is not None:
                svgs[directive.id] = rendered.svg
        if svgs:
            warnings = [
                warning
                for warning in warnings
                if warning != "chart invalid: unavailable evidence source"
            ]
    return ValidatedCharts(svgs=svgs, warnings=warnings)
