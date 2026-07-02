import logging
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException

from models.parent import CreateParentRequest, ParentResponse
from services import supabase_client
from services.auth import get_current_parent_claims

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/parents", tags=["parents"])

PARENTS_TABLE = "parents"


@router.post("/me", response_model=ParentResponse)
async def upsert_current_parent(
    payload: CreateParentRequest, claims: dict = Depends(get_current_parent_claims)
) -> ParentResponse:
    parent_id = claims.get("sub")
    email = claims.get("email")
    if not parent_id or not email:
        raise HTTPException(status_code=401, detail="Token missing subject or email claim")

    parent_row = await supabase_client.upsert_row(
        PARENTS_TABLE,
        {
            "id": parent_id,
            "first_name": payload.first_name,
            "last_name": payload.last_name,
            "email": email,
        },
        on_conflict="id",
    )
    return ParentResponse(**parent_row)
