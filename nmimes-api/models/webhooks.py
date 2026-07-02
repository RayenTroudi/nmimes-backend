from typing import Any

from pydantic import BaseModel


class StripeWebhookEvent(BaseModel):
    id: str
    type: str
    data: dict[str, Any]
