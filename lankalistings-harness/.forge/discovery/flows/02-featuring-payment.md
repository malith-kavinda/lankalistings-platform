# Flow 02 — Seller: feature an approved ad (the revenue flow)

> The product's **only** revenue path — and the one with **no design artefact at all**.
> Requirements: FR-44…FR-48, R-7, FR-22. Acceptance: AC-8, AC-9.
> Evidence for its existence: the `Promote` row action in `my_account_desktop`, the
> `Explore Promotions` upsell in `post_your_ad_final_step_desktop`, the `Plans & Promotions` admin
> sidebar item, and the `PROMOTED` treatment on cards and detail pages.

## Happy path

```mermaid
sequenceDiagram
    actor S as Seller
    participant C as Client
    participant P as payment-service
    participant L as listing-service
    participant G as Payment gateway

    S->>C: Promote (from My Ads or publish upsell)
    C->>P: GET /promotion-plans
    P-->>C: active plans (name, price LKR, duration)
    S->>C: Select a plan
    C->>P: POST /ads/{reference}/featuring
    P->>L: Verify: status == active AND owner == caller
    alt Ad not active, or not owned
        L-->>P: rejected
        P-->>C: 409 AD_NOT_ACTIVE
        Note over C,S: AC-9 — featuring never bypasses moderation (R-7)
    else Eligible
        L-->>P: ok
        P->>P: FeaturingPurchase (initiated),<br/>price captured at purchase time
        P-->>C: redirect / checkout session
        S->>G: Pay in LKR
        G->>P: POST /webhooks/payments/{gateway}
        P->>P: Verify signature;<br/>idempotent on gateway_reference
        P->>P: purchase = settled
        P->>L: Start featured window
        L->>L: featured_until = now + plan.duration
        P-->>S: Receipt
        Note over L: Ad now ranks featured-first<br/>and renders PROMOTED (FR-22)
    end
```

## Rules

| # | Rule | Source |
|---|---|---|
| 1 | Featuring is offered **only** against an `ACTIVE` ad owned by the caller. Verified server-side, never by trusting the client | R-7, FR-44, **AC-9** |
| 2 | Payment capture is not built before an approvable ad exists | `[LOCKED]` — the pack's own build-order instruction |
| 3 | The featured window starts **only** on settled payment — never on initiation | AC-8 |
| 4 | Webhook handling is **idempotent**, keyed on a unique gateway reference. The same settlement delivered twice yields one window | Doc 04 §5 |
| 5 | Plan price is captured **at purchase time** — catalogue prices change | Doc 04 §5 |
| 6 | Featuring expiry returns the ad to ordinary ranking **without** changing its `ACTIVE` status | FR-47 |
| 7 | Featured-first ordering is applied **server-side**, within the requested sort. Three clients must not each invent a ranking | Doc 05 §9 |
| 8 | Money is integer LKR minor units end to end. No float anywhere | NFR-4, D-21 |

## Failure paths that need design

None of these has a screen. All are real and all are user-visible.

| Path | What the seller must see |
|---|---|
| Payment abandoned at the gateway | Ad unchanged, purchase left `initiated`, a clear way to retry |
| Payment fails | Reason, retry, no featured window |
| Payment settles but the featured window fails to start | **The worst case** — money taken, nothing delivered. Needs reconciliation and an operator alert, not just a log line |
| Duplicate webhook | Exactly one window. Silent, correct |
| Featuring an already-featured ad | Extend the window, or reject? Undecided |
| Featured window expires | Does the seller get notified? Undecided |
| Refund | No policy, no surface, no state beyond a `refunded` status |

## Blocked on decisions

This flow cannot be planned, let alone built, until these land:

- **OQ-05** — **no payment gateway is named anywhere in the inputs.** PayHere is the leading LKR
  candidate. Everything else in this flow depends on the answer.
- **OQ-06** — the plan catalogue: names, prices, durations. The admin surface to manage plans exists in
  the sidebar; the plans themselves do not.
- **OQ-11** — the featured-vs-organic ranking interleave: all featured first, or a capped allocation per
  page? Affects both revenue and result quality.
- **Refund policy** — unaddressed in every input.

## Why this flow deserves attention disproportionate to its size

It is small in surface area and large in consequence. It is the only place money changes hands, it is
completely undesigned, it depends on an unchosen third party, and its worst failure mode (paid but not
featured) is invisible to the system unless reconciliation is built deliberately. Slices #28–#32 in
[`../docs/07-harness-backlog.md`](../docs/07-harness-backlog.md) should be sized with that in mind.
