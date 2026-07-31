from datetime import datetime

from sqlalchemy import (
    CHAR,
    CheckConstraint,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects import mysql
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, new_uuid, utc_now


class ReportGenerationRun(Base):
    __tablename__ = "report_generation_runs"
    __table_args__ = (
        UniqueConstraint(
            "trigger_execution_id",
            name="uq_report_generation_runs_trigger_execution",
        ),
        CheckConstraint(
            "origin IN ('trigger', 'user_initiated')",
            name="ck_report_generation_runs_origin",
        ),
        CheckConstraint(
            "state IN ('planning', 'awaiting_selection', 'generating', "
            "'completed', 'failed', 'cancelled', 'expired')",
            name="ck_report_generation_runs_state",
        ),
        Index(
            "ix_report_generation_runs_user_state_updated",
            "user_id",
            "state",
            "updated_at",
        ),
        Index(
            "ix_report_generation_runs_user_created",
            "user_id",
            "created_at",
        ),
    )

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    origin: Mapped[str] = mapped_column(String(32), nullable=False)
    trigger_execution_id: Mapped[str | None] = mapped_column(CHAR(36))
    state: Mapped[str] = mapped_column(String(32), nullable=False)
    active_stage: Mapped[str | None] = mapped_column(String(100))
    launch_context: Mapped[dict] = mapped_column(mysql.JSON, default=dict, nullable=False)
    intent: Mapped[str | None] = mapped_column(Text)
    answers: Mapped[dict] = mapped_column(mysql.JSON, default=dict, nullable=False)
    evidence_scope: Mapped[dict] = mapped_column(mysql.JSON, default=dict, nullable=False)
    pending_decision: Mapped[dict | None] = mapped_column(mysql.JSON)
    plan_options: Mapped[list] = mapped_column(mysql.JSON, default=list, nullable=False)
    selected_option_id: Mapped[str | None] = mapped_column(String(100))
    execution_plan: Mapped[dict | None] = mapped_column(mysql.JSON)
    template_id: Mapped[str | None] = mapped_column(String(100))
    template_version: Mapped[str | None] = mapped_column(String(32))
    resolved_asset_ids: Mapped[list] = mapped_column(
        mysql.JSON,
        default=list,
        nullable=False,
    )
    planner_job_id: Mapped[str | None] = mapped_column(CHAR(36))
    generation_job_id: Mapped[str | None] = mapped_column(CHAR(36))
    draft_content_md: Mapped[str | None] = mapped_column(Text)
    generation_context: Mapped[dict] = mapped_column(
        mysql.JSON,
        default=dict,
        nullable=False,
    )
    usage_json: Mapped[dict] = mapped_column(mysql.JSON, default=dict, nullable=False)
    report_id: Mapped[str | None] = mapped_column(CHAR(36))
    failure_stage: Mapped[str | None] = mapped_column(String(100))
    error_code: Mapped[str | None] = mapped_column(String(100))
    error_message: Mapped[str | None] = mapped_column(Text)
    retry_from: Mapped[str | None] = mapped_column(String(100))
    created_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        default=utc_now,
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        default=utc_now,
        onupdate=utc_now,
        nullable=False,
    )
    expires_at: Mapped[datetime | None] = mapped_column(mysql.DATETIME(fsp=6))
    completed_at: Mapped[datetime | None] = mapped_column(mysql.DATETIME(fsp=6))
    cancelled_at: Mapped[datetime | None] = mapped_column(mysql.DATETIME(fsp=6))


class Report(Base):
    __tablename__ = "reports"
    __table_args__ = (
        UniqueConstraint(
            "generation_run_id",
            name="uq_reports_generation_run",
        ),
        Index("ix_reports_user_created", "user_id", "created_at"),
        CheckConstraint("tokens_used >= 0", name="ck_reports_tokens_nonnegative"),
        CheckConstraint("gen_ms >= 0", name="ck_reports_gen_ms_nonnegative"),
    )

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    generation_run_id: Mapped[str] = mapped_column(
        CHAR(36),
        ForeignKey("report_generation_runs.id", ondelete="RESTRICT"),
        nullable=False,
    )
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    template_id: Mapped[str] = mapped_column(String(100), nullable=False)
    template_version: Mapped[str] = mapped_column(String(32), nullable=False)
    base_family: Mapped[str] = mapped_column(String(100), nullable=False)
    content_md: Mapped[str] = mapped_column(Text, nullable=False)
    html: Mapped[str | None] = mapped_column(Text)
    spec_json: Mapped[dict] = mapped_column(mysql.JSON, nullable=False)
    share_card_spec: Mapped[dict] = mapped_column(mysql.JSON, nullable=False)
    tokens_used: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    gen_ms: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        default=utc_now,
        nullable=False,
    )


class File(Base):
    __tablename__ = "files"
    __table_args__ = (
        Index("ix_files_user_created", "user_id", "created_at"),
        CheckConstraint("size_bytes >= 0", name="ck_files_size_nonnegative"),
    )

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    purpose: Mapped[str] = mapped_column(String(100), nullable=False)
    mime_type: Mapped[str] = mapped_column(String(255), nullable=False)
    size_bytes: Mapped[int] = mapped_column(Integer, nullable=False)
    sha256: Mapped[str] = mapped_column(String(64), nullable=False)
    storage_key: Mapped[str] = mapped_column(String(500), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        default=utc_now,
        nullable=False,
    )


class ReportShare(Base):
    __tablename__ = "report_shares"
    __table_args__ = (
        Index("ix_report_shares_user_created", "user_id", "created_at"),
        Index("ix_report_shares_status_expiry", "status", "expires_at"),
        CheckConstraint(
            "status IN ('active', 'revoked', 'expired')",
            name="ck_report_shares_status",
        ),
    )

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    report_id: Mapped[str] = mapped_column(
        CHAR(36),
        ForeignKey("reports.id", ondelete="CASCADE"),
        nullable=False,
    )
    user_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    status: Mapped[str] = mapped_column(String(32), default="active", nullable=False)
    expires_at: Mapped[datetime | None] = mapped_column(mysql.DATETIME(fsp=6))
    snapshot_content_md: Mapped[str] = mapped_column(Text, nullable=False)
    snapshot_spec_json: Mapped[dict] = mapped_column(mysql.JSON, nullable=False)
    snapshot_html: Mapped[str | None] = mapped_column(Text)
    media_map_json: Mapped[dict] = mapped_column(mysql.JSON, default=dict, nullable=False)
    share_card_file_id: Mapped[str | None] = mapped_column(
        CHAR(36),
        ForeignKey("files.id", ondelete="SET NULL"),
    )
    created_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        default=utc_now,
        nullable=False,
    )
    revoked_at: Mapped[datetime | None] = mapped_column(mysql.DATETIME(fsp=6))
