import logging

import stripe
from fastapi import APIRouter, Header, HTTPException, Request

from config import get_settings
from services import supabase_client

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/webhooks", tags=["webhooks"])

PARENTS_TABLE = "parents"


@router.post("/stripe")
async def stripe_webhook(request: Request, stripe_signature: str = Header(alias="Stripe-Signature")) -> dict:
    settings = get_settings()
    payload = await request.body()

    try:
        event = stripe.Webhook.construct_event(
            payload=payload,
            sig_header=stripe_signature,
            secret=settings.stripe_webhook_secret,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Invalid payload") from exc
    except stripe.error.SignatureVerificationError as exc:
        raise HTTPException(status_code=400, detail="Invalid signature") from exc

    event_type = event["type"]
    data_object = event["data"]["object"]

    if event_type == "customer.subscription.created":
        await _update_subscription_status(data_object, status="active")
    elif event_type == "customer.subscription.deleted":
        await _update_subscription_status(data_object, status="canceled")
    else:
        logger.info("Unhandled Stripe event type: %s", event_type)

    return {"received": True}


async def _update_subscription_status(subscription: dict, status: str) -> None:
    customer_id = subscription.get("customer")
    if not customer_id:
        logger.warning("Stripe subscription event missing customer id")
        return

    await supabase_client.update_rows(
        PARENTS_TABLE,
        filters={"stripe_customer_id": f"eq.{customer_id}"},
        data={"subscription_status": status},
    )
