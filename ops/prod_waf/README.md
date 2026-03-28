# Prod WAF

This directory holds the low-risk regional WAF setup for Mixroom's public APIs.

The stack creates one regional WebACL intended to be shared by:

- `mixroom-app-api-prod`
- `mixroom-llm-proxy-prod`

Scope:

- AWS managed common protections
- AWS managed known-bad-input protections

This intentionally avoids aggressive per-IP rate blocks for now because the app is consumer/mobile facing and carrier NATs can make low rate limits risky.

Deploy:

```bash
ops/prod_waf/deploy_api_waf.sh
```
