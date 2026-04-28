from typing import Annotated, Literal, Optional, TypedDict

from langchain_core.messages import BaseMessage
from langgraph.graph.message import add_messages
from pydantic import BaseModel, ConfigDict, Field, field_validator

ClassificationLabel = Literal["Spam", "Normal", "Urgent"]


class ClassifyResult(BaseModel):
    model_config = ConfigDict(extra="forbid")
    summary: str
    classification: ClassificationLabel


class AnalysisResult(BaseModel):
    model_config = ConfigDict(extra="forbid")
    analysis: str


class TemplateResult(BaseModel):
    model_config = ConfigDict(extra="forbid")
    template: str


class InputState(BaseModel):
    model_config = ConfigDict(extra="forbid")

    subject: str
    title: str
    content: str

    @field_validator("subject", "title", "content")
    @classmethod
    def not_empty(cls, value: str):
        if not value or not value.strip():
            raise ValueError("Input field cannot be empty")
        return value.strip()


class OutputState(BaseModel):
    model_config = ConfigDict(extra="forbid")

    summary: str
    classification: ClassificationLabel
    analysis: str
    actions: list[str] = Field(default_factory=list)
    message: str

    @field_validator("summary", "analysis", "message")
    @classmethod
    def not_empty(cls, value: str):
        if not value or not value.strip():
            raise ValueError("Output text fields cannot be empty")
        return value.strip()


class EmailState(TypedDict):
    messages: Annotated[list[BaseMessage], add_messages]
    subject: str
    title: str
    content: str
    summary: Optional[str]
    classification: Optional[str]
    analysis: Optional[str]
    email_template: Optional[str]
    actions: list[str]
    final_message: Optional[str]
