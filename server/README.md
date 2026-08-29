# Backend deployment guardrails

This server is a prototype boundary, not a public authentication system. The
`SEENA_APP_TOKEN` request header is a static proof-of-concept token and must be
replaced with a real per-device or per-session trust mechanism before a public
release.

For every internet-facing deployment, configure all of:

- `SEENA_KV_REST_API_URL`
- `SEENA_KV_REST_API_TOKEN`
- `SEENA_DAILY_COST_UNIT_LIMIT`

The provider boundary fails closed with `503 quota_unavailable_or_exhausted`
when any quota variable is missing, malformed, exhausted, or its store is
unavailable. This prevents a quota-store outage from becoming an unbounded paid
provider call.

Only an explicitly local development server may omit the quota variables:
`SEENA_DEPLOYMENT_MODE=local-development`. Do not set that mode in a public
deployment.

Calls are charged immediately before the external provider access, after
request parsing and schema validation. Network ambiguity after that charge can
still produce an unknown provider outcome; callers should use their existing
local/operator fallback rather than retrying paid requests blindly.
