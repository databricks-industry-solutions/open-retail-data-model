"""Authorization and retrieval policy for associate real-time lookups."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional, Sequence, Set

from .envelope import CAPABILITIES, AssociateLookupRequest

# Roles that may look across stores within their authorized set.
CROSS_STORE_ROLES = frozenset({"supervisor", "store_manager", "district_manager"})

# Fields never returned on associate-facing payloads.
RESTRICTED_FIELDS = frozenset({
    "profile_id",
    "customer_id",
    "first_name",
    "last_name",
    "middle_name",
    "date_of_birth",
    "loyalty_id",
    "contact_value",
    "tax_id",
    "unit_cost",
    "margin",
    "hourly_labor_cost",
    "loss_prevention_flag",
    "shrinkage_amount",
    "payment_method",
    "card_brand",
})

PRODUCT_CAPABILITIES = frozenset({
    "get_product_availability",
    "get_product_location",
    "get_price_and_promotions",
})


@dataclass(frozen=True)
class AccessDecision:
    allowed: bool
    reason_code: str
    decision: str  # allow | deny

    def as_dict(self) -> dict:
        return {
            "decision": self.decision,
            "reason_code": self.reason_code,
            "allowed": self.allowed,
        }


def _authorized_stores(request: AssociateLookupRequest) -> Set[str]:
    stores = set(request.authorized_store_ids or ())
    if request.store_id:
        stores.add(request.store_id)
    return {s for s in stores if s}


def validate_request(request: AssociateLookupRequest) -> Optional[AccessDecision]:
    """Return a deny decision for invalid requests; None if structurally valid."""
    if not request.request_id:
        return AccessDecision(False, "MISSING_REQUEST_ID", "deny")
    if not request.request_correlation_id:
        return AccessDecision(False, "MISSING_CORRELATION_ID", "deny")
    if not request.associate_id:
        return AccessDecision(False, "MISSING_ASSOCIATE_ID", "deny")
    if not request.associate_role:
        return AccessDecision(False, "MISSING_ASSOCIATE_ROLE", "deny")
    if not request.store_id:
        return AccessDecision(False, "MISSING_STORE_ID", "deny")
    if request.requested_capability not in CAPABILITIES:
        return AccessDecision(False, "UNKNOWN_CAPABILITY", "deny")
    if request.channel not in {"mobile", "kiosk", "pos", "dashboard", "api", "test"}:
        return AccessDecision(False, "INVALID_CHANNEL", "deny")

    cap = request.requested_capability
    if cap in PRODUCT_CAPABILITIES:
        if not request.product_id and not request.product_search_term:
            return AccessDecision(False, "MISSING_PRODUCT_IDENTIFIER", "deny")
        # Fuzzy / free-text search is denied unless an exact product_id is supplied.
        if request.product_search_term and not request.product_id:
            return AccessDecision(False, "PRODUCT_SEARCH_REQUIRES_EXACT_ID", "deny")
    if cap == "get_order_fulfillment_status":
        if not request.order_id:
            return AccessDecision(False, "MISSING_ORDER_ID", "deny")
        # Broad search text is not a valid order locator.
        if request.product_search_term and not request.order_id:
            return AccessDecision(False, "ORDER_BROAD_SEARCH_DENIED", "deny")
    return None


def authorize(request: AssociateLookupRequest) -> AccessDecision:
    """Least-privilege store and capability authorization."""
    invalid = validate_request(request)
    if invalid is not None:
        return invalid

    allowed_stores = _authorized_stores(request)
    if request.store_id not in allowed_stores:
        return AccessDecision(False, "STORE_SCOPE_DENIED", "deny")

    # Non-cross-store roles may only query their single assigned store.
    if (
        request.associate_role not in CROSS_STORE_ROLES
        and len(allowed_stores) > 1
        and request.store_id not in (request.authorized_store_ids or (request.store_id,))
    ):
        # Still allow if the only asserted store matches home scope.
        pass

    if request.associate_role not in CROSS_STORE_ROLES:
        # Store associates: deny if authorized_store_ids is non-empty and excludes store_id.
        explicit = set(request.authorized_store_ids or ())
        if explicit and request.store_id not in explicit:
            return AccessDecision(False, "STORE_SCOPE_DENIED", "deny")

    cap = request.requested_capability
    if cap == "get_order_fulfillment_status":
        # Customer-specific detail requires verification context when flagged by data.
        # Policy always requires an exact order_id (already validated) and never
        # accepts customer_id alone as a locator.
        if request.customer_id and not (
            request.customer_context_present and request.customer_verified
        ):
            return AccessDecision(
                False, "CUSTOMER_CONTEXT_REQUIRES_VERIFICATION", "deny"
            )

    if request.customer_id and not (
        request.customer_context_present and request.customer_verified
    ):
        # Customer identifiers on any capability without verification are denied.
        return AccessDecision(False, "CUSTOMER_PII_CONTEXT_DENIED", "deny")

    return AccessDecision(True, "STORE_SCOPE_ALLOWED", "allow")


def strip_restricted_fields(row: Optional[dict]) -> Optional[dict]:
    if row is None:
        return None
    return {k: v for k, v in row.items() if k not in RESTRICTED_FIELDS}


def strip_restricted_rows(rows: Sequence[dict]) -> list:
    return [strip_restricted_fields(r) for r in rows]
