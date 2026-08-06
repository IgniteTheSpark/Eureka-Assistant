from typing import Literal

from pydantic import BaseModel


class PendingActionResolve(BaseModel):
    contact_id: str
    resolution_source: Literal["card", "chat"] = "card"


class PendingActionCancel(BaseModel):
    resolution_source: Literal["card", "chat"] = "card"
