from datetime import datetime, timezone
from typing import Literal

from pydantic import BaseModel, Field, field_serializer


def _as_utc_z(value: datetime | None) -> str | None:
    if value is None:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


class BindingInfoRequest(BaseModel):
    card_sn: str = Field(max_length=160)


class BindRequest(BaseModel):
    card_sn: str = Field(max_length=160)
    card_device_uuid: str = Field(max_length=255)
    card_mac: str | None = Field(default=None, max_length=64)
    card_mac_from: str | None = Field(default=None, max_length=64)
    card_name: str | None = Field(default=None, max_length=160)
    card_nick: str | None = Field(default=None, max_length=160)
    card_app_uuid: str = Field(max_length=255)


class UnbindRequest(BaseModel):
    delete_data: bool = False


class BindingPublic(BaseModel):
    binding_id: str
    card_id: str
    card_nick: str | None
    card_app_uuid: str
    bind_status: Literal["bound", "unbound"]
    bind_time: datetime | None
    unbind_time: datetime | None
    created_at: datetime | None
    updated_at: datetime | None
    card_sn: str
    card_device_uuid: str
    card_mac: str | None
    card_mac_from: str | None
    card_name: str | None

    @field_serializer(
        "bind_time",
        "unbind_time",
        "created_at",
        "updated_at",
    )
    def serialize_timestamp(self, value: datetime | None) -> str | None:
        return _as_utc_z(value)


class ConnectHint(BaseModel):
    card_app_uuid: str
    card_device_uuid: str
    card_name: str | None
    card_mac: str | None


class BindingInfoResponse(BaseModel):
    ok: bool = True
    card_sn: str
    bindable: bool
    state: Literal[
        "never_bound_by_me",
        "bound_by_other",
        "bound_by_me",
        "previously_bound_by_me",
    ]
    current_binding: BindingPublic | None
    latest_user_binding: BindingPublic | None
    connect_hint: ConnectHint | None


class BindResponse(BaseModel):
    ok: bool = True
    action: Literal["created", "updated"]
    binding: BindingPublic


class BindingListResponse(BaseModel):
    ok: bool = True
    bindings: list[BindingPublic]


class UnbindResponse(BaseModel):
    ok: bool = True
    delete_data: bool
    binding: BindingPublic
