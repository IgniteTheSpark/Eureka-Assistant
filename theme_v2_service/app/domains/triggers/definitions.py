from dataclasses import dataclass


@dataclass(frozen=True)
class TriggerDefinition:
    trigger_type: str
    signal_type: str
    workflow_type: str
    minimum_days: int | None = None
    minimum_assets: int | None = None


TRIGGER_DEFINITIONS = {
    "proactive_summary": TriggerDefinition(
        trigger_type="proactive_summary",
        signal_type="asset_created",
        workflow_type="report_generation",
        minimum_days=7,
        minimum_assets=7,
    ),
    "pre_event_report": TriggerDefinition(
        trigger_type="pre_event_report",
        signal_type="time",
        workflow_type="report_generation",
    ),
}
