"""Associate Real-Time Data Access — request/response envelope helpers."""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from typing import Any, Mapping, MutableMapping, Optional, Sequence


RESPONSE_STATUSES = frozenset({
    "SUCCESS",
    "NOT_FOUND",
    "NOT_AVAILABLE",
    "STALE_DATA",
    "ACCESS_DENIED",
    "INVALID_REQUEST",
    "PARTIAL_RESULT",
    "UPSTREAM_DATA_DELAY",
})

CAPABILITIES = frozenset({
    "get_product_availability",
    "get_product_location",
    "get_price_and_promotions",
    "get_order_fulfillment_status",
    "get_store_operations_context",
    "get_associate_context_summary",
})


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


@dataclass(frozen=True)
class AssociateLookupRequest:
    request_id: str
    request_timestamp: datetime
    store_id: str
    associate_id: str
    associate_role: str
    channel: str
    requested_capability: str
    request_correlation_id: str
    customer_context_present: bool = False
    customer_verified: bool = False
    customer_id: Optional[str] = None
    product_id: Optional[str] = None
    product_search_term: Optional[str] = None
    order_id: Optional[str] = None
    authorized_store_ids: Sequence[str] = field(default_factory=tuple)

    @classmethod
    def from_mapping(cls, raw: Mapping[str, Any]) -> "AssociateLookupRequest":
        ts = raw.get("request_timestamp") or utc_now()
        if isinstance(ts, str):
            ts = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        stores = raw.get("authorized_store_ids") or ()
        return cls(
            request_id=str(raw.get("request_id") or ""),
            request_timestamp=ts,
            store_id=str(raw.get("store_id") or ""),
            associate_id=str(raw.get("associate_id") or ""),
            associate_role=str(raw.get("associate_role") or ""),
            channel=str(raw.get("channel") or "api"),
            requested_capability=str(raw.get("requested_capability") or ""),
            request_correlation_id=str(
                raw.get("request_correlation_id") or raw.get("correlation_id") or ""
            ),
            customer_context_present=bool(raw.get("customer_context_present", False)),
            customer_verified=bool(raw.get("customer_verified", False)),
            customer_id=raw.get("customer_id"),
            product_id=raw.get("product_id"),
            product_search_term=raw.get("product_search_term"),
            order_id=raw.get("order_id"),
            authorized_store_ids=tuple(stores),
        )


@dataclass
class AssociateLookupResponse:
    request_id: str
    status: str
    data: Any
    warnings: list
    freshness: MutableMapping[str, Any]
    source_lineage: MutableMapping[str, Any]
    access_decision: MutableMapping[str, Any]
    generated_at: datetime
    correlation_id: str

    def to_dict(self) -> dict:
        payload = asdict(self)
        payload["generated_at"] = self.generated_at.isoformat().replace("+00:00", "Z")
        return payload


def make_response(
    request: AssociateLookupRequest,
    *,
    status: str,
    data: Any = None,
    warnings: Optional[Sequence[str]] = None,
    freshness: Optional[Mapping[str, Any]] = None,
    source_lineage: Optional[Mapping[str, Any]] = None,
    access_decision: Optional[Mapping[str, Any]] = None,
    generated_at: Optional[datetime] = None,
) -> AssociateLookupResponse:
    if status not in RESPONSE_STATUSES:
        raise ValueError(f"unknown response status: {status}")
    return AssociateLookupResponse(
        request_id=request.request_id,
        status=status,
        data=data,
        warnings=list(warnings or []),
        freshness=dict(freshness or {}),
        source_lineage=dict(source_lineage or {}),
        access_decision=dict(access_decision or {}),
        generated_at=generated_at or utc_now(),
        correlation_id=request.request_correlation_id,
    )
