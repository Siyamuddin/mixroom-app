# DevOps TODO

Deployment and infrastructure tasks that sit outside normal app feature work.

## Priority Guide

- `P0`: blocker for release or core production function
- `P1`: important production hardening, but not a blocker
- `P2`: nice to have or later optimization

## Current Items

### P1: Finish PostHog Reverse Proxy

Status:
- not a blocker
- recommended before broader production rollout

Why it matters:
- PostHog works without it
- dashboards and event ingestion still work without it
- backend/server-side events still work without it
- the main benefit is better client-side capture reliability, especially against ad blockers or stricter network filtering

What is restricted if you skip it:
- no core PostHog feature is disabled
- the likely downside is undercounted Flutter/client analytics events
- server-side authoritative events are much less affected

What to do:
1. Create the DNS `CNAME` for `v.mixroom.ai` pointing to the PostHog-generated proxy target.
2. If using Cloudflare or a similar DNS proxy, disable proxying for that `CNAME`.
3. Wait for PostHog to mark the reverse proxy as `live`.
4. Update Flutter `POSTHOG_HOST` to `https://v.mixroom.ai`.
5. Send a real client event and confirm it appears in PostHog.

Current Mixroom recommendation:
- keep using PostHog now
- treat the reverse proxy as production hardening, not launch-blocking infra

## Related Docs

- [ANALYTICS.md](ANALYTICS.md)
- [DEVELOPER_TODO.md](DEVELOPER_TODO.md)
