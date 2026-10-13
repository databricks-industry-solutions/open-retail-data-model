"""Governed associate real-time lookup service (deterministic, testable).

This module is the structured request/response contract for Real-Time Data
Access. It does not call external SaaS. Callers supply in-memory tables or
DataFrame-like row maps representing the curated gold products.
"""

from __future__ import annotations

import hashlib
import time
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Callable, Dict, Iterable, List, Mapping, Optional, Sequence

from .envelope import (
    AssociateLookupRequest,
    AssociateLookupResponse,
    make_response,
    utc_now,
)
from .policy import AccessDecision, authorize, strip_restricted_fields


def _hash_id(value: Optional[str]) -> Optional[str]:
    if not value:
        return None
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _freshness_payload(row: Optional[Mapping[str, Any]]) -> dict:
    if not row:
        return {"freshness_status": "UNKNOWN"}
    return {
        "freshness_status": row.get("freshness_status", "UNKNOWN"),
        "freshness_lag_minutes": row.get("freshness_lag_minutes"),
        "source_event_timestamp": row.get("source_event_timestamp")
        or row.get("last_event_timestamp"),
        "source_ingest_timestamp": row.get("source_ingest_timestamp"),
        "current_state_updated_at": row.get("current_state_updated_at"),
    }


def _lineage_payload(row: Optional[Mapping[str, Any]], domain: str) -> dict:
    if not row:
        return {"domains": [domain], "source_system": None}
    return {
        "domains": [domain],
        "source_system": row.get("source_system"),
        "explanation": row.get("explanation"),
    }


def _status_for_freshness(base: str, freshness_status: Optional[str]) -> str:
    if base != "SUCCESS":
        return base
    if freshness_status == "stale":
        return "STALE_DATA"
    if freshness_status == "delayed":
        return "UPSTREAM_DATA_DELAY"
    return base


@dataclass
class AssociateLookupService:
    """Capability router over curated associate context tables."""

    inventory_rows: Sequence[Mapping[str, Any]] = field(default_factory=list)
    price_rows: Sequence[Mapping[str, Any]] = field(default_factory=list)
    order_rows: Sequence[Mapping[str, Any]] = field(default_factory=list)
    operations_rows: Sequence[Mapping[str, Any]] = field(default_factory=list)
    freshness_rows: Sequence[Mapping[str, Any]] = field(default_factory=list)
    audit_sink: Optional[Callable[[dict], None]] = None
    clock: Callable[[], datetime] = utc_now

    def lookup(self, raw_request: Mapping[str, Any]) -> AssociateLookupResponse:
        started = time.perf_counter()
        request = AssociateLookupRequest.from_mapping(raw_request)
        decision = authorize(request)
        if not decision.allowed:
            invalid_reasons = {
                "MISSING_REQUEST_ID",
                "MISSING_CORRELATION_ID",
                "MISSING_ASSOCIATE_ID",
                "MISSING_ASSOCIATE_ROLE",
                "MISSING_STORE_ID",
                "UNKNOWN_CAPABILITY",
                "INVALID_CHANNEL",
                "MISSING_PRODUCT_IDENTIFIER",
                "MISSING_ORDER_ID",
                "PRODUCT_SEARCH_REQUIRES_EXACT_ID",
            }
            status = (
                "INVALID_REQUEST"
                if decision.reason_code in invalid_reasons
                else "ACCESS_DENIED"
            )
            response = make_response(
                request,
                status=status,
                data=None,
                warnings=[],
                freshness={},
                source_lineage={},
                access_decision=decision.as_dict(),
                generated_at=self.clock(),
            )
            self._audit(request, decision, response, started)
            return response

        handler = {
            "get_product_availability": self._product_availability,
            "get_product_location": self._product_location,
            "get_price_and_promotions": self._price_promotions,
            "get_order_fulfillment_status": self._order_status,
            "get_store_operations_context": self._operations,
            "get_associate_context_summary": self._summary,
        }[request.requested_capability]

        response = handler(request, decision)
        self._audit(request, decision, response, started)
        return response

    def _audit(
        self,
        request: AssociateLookupRequest,
        decision: AccessDecision,
        response: AssociateLookupResponse,
        started: float,
    ) -> None:
        if self.audit_sink is None:
            return
        latency_ms = int((time.perf_counter() - started) * 1000)
        self.audit_sink({
            "associate_lookup_audit_id": f"AUD-{request.request_id}",
            "request_id": request.request_id,
            "correlation_id": request.request_correlation_id,
            "request_timestamp": request.request_timestamp,
            "generated_at": response.generated_at,
            "associate_id": request.associate_id,
            "associate_role": request.associate_role,
            "channel": request.channel,
            "store_id": request.store_id,
            "capability": request.requested_capability,
            "access_decision": decision.decision,
            "access_reason_code": decision.reason_code,
            "response_status": response.status,
            "latency_ms": latency_ms,
            "domains_accessed": ",".join(
                response.source_lineage.get("domains") or []
            ),
            "data_classification": "associate_ops",
            "product_id_hash": _hash_id(request.product_id),
            "order_id_hash": _hash_id(request.order_id),
            "record_source": "associate_realtime_access",
            "load_timestamp": response.generated_at,
        })

    def _find_inventory(self, request: AssociateLookupRequest) -> Optional[dict]:
        for row in self.inventory_rows:
            if (
                row.get("product_id") == request.product_id
                and row.get("store_id") == request.store_id
            ):
                return dict(row)
        return None

    def _find_price(self, request: AssociateLookupRequest) -> Optional[dict]:
        for row in self.price_rows:
            if (
                row.get("product_id") == request.product_id
                and row.get("store_id") == request.store_id
            ):
                return dict(row)
        return None

    def _find_order(self, request: AssociateLookupRequest) -> Optional[dict]:
        for row in self.order_rows:
            if row.get("order_id") == request.order_id:
                return dict(row)
        return None

    def _product_availability(
        self, request: AssociateLookupRequest, decision: AccessDecision
    ) -> AssociateLookupResponse:
        row = strip_restricted_fields(self._find_inventory(request))
        if row is None:
            return make_response(
                request,
                status="NOT_FOUND",
                data=None,
                access_decision=decision.as_dict(),
                source_lineage={"domains": ["inventory"]},
                generated_at=self.clock(),
            )
        warnings = [w for w in [row.get("warning")] if w]
        status = _status_for_freshness("SUCCESS", row.get("freshness_status"))
        return make_response(
            request,
            status=status,
            data=row,
            warnings=warnings,
            freshness=_freshness_payload(row),
            source_lineage=_lineage_payload(row, "inventory"),
            access_decision=decision.as_dict(),
            generated_at=self.clock(),
        )

    def _product_location(
        self, request: AssociateLookupRequest, decision: AccessDecision
    ) -> AssociateLookupResponse:
        row = strip_restricted_fields(self._find_inventory(request))
        if row is None:
            return make_response(
                request,
                status="NOT_FOUND",
                data=None,
                access_decision=decision.as_dict(),
                source_lineage={"domains": ["inventory"]},
                generated_at=self.clock(),
            )
        loc = row.get("sales_floor_or_backroom_location")
        location_basis = row.get("location_basis") or (
            "event_location_code" if loc else "not_modeled"
        )
        if not loc:
            return make_response(
                request,
                status="NOT_AVAILABLE",
                data={
                    "product_id": row.get("product_id"),
                    "store_id": row.get("store_id"),
                    "sales_floor_or_backroom_location": None,
                    "location_basis": location_basis,
                },
                warnings=[
                    "ORDM has no shelf/bay/planogram geo model; only optional "
                    "free-text location_code from inventory events. Location is NOT_AVAILABLE."
                ],
                freshness=_freshness_payload(row),
                source_lineage=_lineage_payload(row, "inventory"),
                access_decision=decision.as_dict(),
                generated_at=self.clock(),
            )
        data = {
            "product_id": row.get("product_id"),
            "store_id": row.get("store_id"),
            "sales_floor_or_backroom_location": loc,
            "location_basis": location_basis,
            "stock_status": row.get("stock_status"),
            "inventory_basis": row.get("inventory_basis"),
            "nearby_store_with_stock_id": row.get("nearby_store_with_stock_id"),
            "nearby_store_match_basis": row.get("nearby_store_match_basis"),
        }
        status = _status_for_freshness("SUCCESS", row.get("freshness_status"))
        warnings = [w for w in [row.get("warning")] if w]
        warnings.append(
            "Location is optional free-text location_code only — not shelf/bay coordinates."
        )
        return make_response(
            request,
            status=status,
            data=data,
            warnings=warnings,
            freshness=_freshness_payload(row),
            source_lineage=_lineage_payload(row, "inventory"),
            access_decision=decision.as_dict(),
            generated_at=self.clock(),
        )

    def _price_promotions(
        self, request: AssociateLookupRequest, decision: AccessDecision
    ) -> AssociateLookupResponse:
        row = strip_restricted_fields(self._find_price(request))
        inv = self._find_inventory(request)
        if row is None:
            # Inventory present but price feed missing => partial / delay.
            if inv is not None:
                return make_response(
                    request,
                    status="PARTIAL_RESULT",
                    data={
                        "product_id": request.product_id,
                        "store_id": request.store_id,
                        "inventory_stock_status": inv.get("stock_status"),
                        "price": None,
                    },
                    warnings=["Price/promotion domain unavailable for this product/store."],
                    freshness=_freshness_payload(inv),
                    source_lineage={"domains": ["inventory"], "missing_domains": ["price"]},
                    access_decision=decision.as_dict(),
                    generated_at=self.clock(),
                )
            return make_response(
                request,
                status="NOT_FOUND",
                data=None,
                access_decision=decision.as_dict(),
                source_lineage={"domains": ["price"]},
                generated_at=self.clock(),
            )
        status = _status_for_freshness("SUCCESS", row.get("freshness_status"))
        return make_response(
            request,
            status=status,
            data=row,
            warnings=[w for w in [row.get("warning")] if w],
            freshness=_freshness_payload(row),
            source_lineage=_lineage_payload(row, "price"),
            access_decision=decision.as_dict(),
            generated_at=self.clock(),
        )

    def _order_status(
        self, request: AssociateLookupRequest, decision: AccessDecision
    ) -> AssociateLookupResponse:
        row = strip_restricted_fields(self._find_order(request))
        if row is None:
            return make_response(
                request,
                status="NOT_FOUND",
                data=None,
                access_decision=decision.as_dict(),
                source_lineage={"domains": ["order"]},
                generated_at=self.clock(),
            )
        if row.get("store_id") != request.store_id:
            # Store associates only see orders for their store unless cross-store role.
            from .policy import CROSS_STORE_ROLES
            if request.associate_role not in CROSS_STORE_ROLES:
                denied = AccessDecision(False, "ORDER_STORE_SCOPE_DENIED", "deny")
                return make_response(
                    request,
                    status="ACCESS_DENIED",
                    data=None,
                    access_decision=denied.as_dict(),
                    source_lineage={"domains": ["order"]},
                    generated_at=self.clock(),
                )
        if row.get("requires_customer_verification") and not (
            request.customer_context_present and request.customer_verified
        ):
            denied = AccessDecision(
                False, "ORDER_REQUIRES_CUSTOMER_VERIFICATION", "deny"
            )
            return make_response(
                request,
                status="ACCESS_DENIED",
                data=None,
                warnings=["Customer verification required for this order detail."],
                access_decision=denied.as_dict(),
                source_lineage={"domains": ["order"]},
                generated_at=self.clock(),
            )
        status = _status_for_freshness("SUCCESS", row.get("freshness_status"))
        return make_response(
            request,
            status=status,
            data=row,
            warnings=[w for w in [row.get("warning")] if w],
            freshness=_freshness_payload(row),
            source_lineage=_lineage_payload(row, "order"),
            access_decision=decision.as_dict(),
            generated_at=self.clock(),
        )

    def _operations(
        self, request: AssociateLookupRequest, decision: AccessDecision
    ) -> AssociateLookupResponse:
        rows = [
            strip_restricted_fields(dict(r))
            for r in self.operations_rows
            if r.get("store_id") == request.store_id
        ]
        rows = [r for r in rows if r is not None]
        if not rows:
            return make_response(
                request,
                status="NOT_AVAILABLE",
                data=[],
                warnings=["No operational signals available for this store."],
                access_decision=decision.as_dict(),
                source_lineage={"domains": ["operations"]},
                generated_at=self.clock(),
            )
        worst = "fresh"
        for r in rows:
            fs = r.get("freshness_status")
            if fs == "stale":
                worst = "stale"
            elif fs == "delayed" and worst != "stale":
                worst = "delayed"
        status = _status_for_freshness("SUCCESS", worst)
        return make_response(
            request,
            status=status,
            data=rows,
            warnings=[w for r in rows for w in [r.get("warning")] if w],
            freshness={"freshness_status": worst, "signal_count": len(rows)},
            source_lineage={"domains": ["operations"]},
            access_decision=decision.as_dict(),
            generated_at=self.clock(),
        )

    def _summary(
        self, request: AssociateLookupRequest, decision: AccessDecision
    ) -> AssociateLookupResponse:
        """Cross-domain summary; partial when some domains are missing."""
        parts: Dict[str, Any] = {}
        warnings: List[str] = []
        domains: List[str] = []
        missing: List[str] = []

        if request.product_id:
            inv = strip_restricted_fields(self._find_inventory(request))
            price = strip_restricted_fields(self._find_price(request))
            if inv:
                parts["inventory"] = inv
                domains.append("inventory")
            else:
                missing.append("inventory")
            if price:
                parts["price"] = price
                domains.append("price")
            else:
                missing.append("price")
                warnings.append("Price domain unavailable.")
        if request.order_id:
            order = strip_restricted_fields(self._find_order(request))
            if order:
                parts["order"] = order
                domains.append("order")
            else:
                missing.append("order")

        ops = [
            strip_restricted_fields(dict(r))
            for r in self.operations_rows
            if r.get("store_id") == request.store_id
        ]
        ops = [r for r in ops if r is not None]
        if ops:
            parts["operations"] = ops
            domains.append("operations")
        else:
            missing.append("operations")

        if not parts:
            return make_response(
                request,
                status="NOT_FOUND",
                data=None,
                access_decision=decision.as_dict(),
                source_lineage={"domains": [], "missing_domains": missing},
                generated_at=self.clock(),
            )

        status = "PARTIAL_RESULT" if missing else "SUCCESS"
        # Escalate freshness if any included row is delayed/stale.
        freshness_status = "fresh"
        for key in ("inventory", "price", "order"):
            row = parts.get(key)
            if isinstance(row, Mapping):
                fs = row.get("freshness_status")
                if fs == "stale":
                    freshness_status = "stale"
                elif fs == "delayed" and freshness_status != "stale":
                    freshness_status = "delayed"
        if status == "SUCCESS":
            status = _status_for_freshness(status, freshness_status)

        return make_response(
            request,
            status=status,
            data=parts,
            warnings=warnings,
            freshness={"freshness_status": freshness_status},
            source_lineage={"domains": domains, "missing_domains": missing},
            access_decision=decision.as_dict(),
            generated_at=self.clock(),
        )


def current_state_from_events(
    events: Iterable[Mapping[str, Any]],
    *,
    entity_keys: Sequence[str],
) -> List[dict]:
    """Derive current-state maps from an ordered event stream.

    Latest event wins by (event_timestamp, ingest_timestamp). Duplicate
    event ids are collapsed to a single occurrence (first retained for
    ordering keys, last payload wins only when timestamps are equal and
    later in input — callers should sort first for determinism).
    """
    by_id: Dict[str, Mapping[str, Any]] = {}
    for ev in events:
        eid = ev.get("associate_context_event_id")
        if eid is None:
            continue
        by_id[str(eid)] = ev  # idempotent: same id overwrites with same/latest payload

    ranked: Dict[tuple, Mapping[str, Any]] = {}
    for ev in by_id.values():
        key = tuple(ev.get(k) for k in entity_keys)
        if any(v is None for v in key):
            continue
        prev = ranked.get(key)
        if prev is None:
            ranked[key] = ev
            continue
        prev_ts = (prev.get("event_timestamp"), prev.get("ingest_timestamp"))
        cur_ts = (ev.get("event_timestamp"), ev.get("ingest_timestamp"))
        if cur_ts >= prev_ts:
            ranked[key] = ev
    return [dict(v) for v in ranked.values()]
