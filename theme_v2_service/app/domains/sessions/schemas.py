from typing import Literal

from pydantic import BaseModel, Field, model_validator


class SessionCreate(BaseModel):
    session_type: Literal["chat"] = "chat"
    subject_type: str | None = Field(default=None, max_length=64)
    subject_id: str | None = Field(default=None, max_length=128)
    peek_only: bool = False

    @model_validator(mode="after")
    def paired_subject(self) -> "SessionCreate":
        if bool(self.subject_type) != bool(self.subject_id):
            raise ValueError("subject_type and subject_id must be supplied together")
        return self


class SessionContextUpdate(BaseModel):
    add: list[str] = Field(default_factory=list, max_length=50)
    remove: list[str] = Field(default_factory=list, max_length=50)


class ChatRequest(BaseModel):
    user_text: str = Field(min_length=1, max_length=20_000)
    session_id: str = Field(default="", max_length=36)
