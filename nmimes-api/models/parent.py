from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field


class CreateParentRequest(BaseModel):
    first_name: str = Field(..., min_length=1)
    last_name: str = Field(..., min_length=1)


class ParentResponse(BaseModel):
    id: UUID
    first_name: str
    last_name: str
    email: str
    subscription_status: Literal["free", "active", "canceled", "past_due"]
    created_at: datetime
    updated_at: datetime
