# Design — [feature or fix]

## Current behavior

Describe the verified flow with file/symbol/API/data evidence.

## Proposed behavior

Describe the smallest complete change and how it satisfies each requirement.

## Affected components

| Repository/component | Current symbol/path | Proposed change |
|---|---|---|
| [repo/module] | [path/symbol] | [change] |

## Interface changes

Document HTTP routes, Kafka events, commands, payloads, responses, status codes, compatibility, and OpenAPI updates. State “None” when not applicable.

## Data design

- Schemas/tables/models:
- Migration/seed/backfill:
- Transaction boundary:
- Idempotency/concurrency:
- Data retention/rollback:

Never include credentials or production data.

## UI and state

- Routes and role metadata:
- Feature components/hooks/services:
- Loading/empty/error/success behavior:
- Accessibility:

## Security

- Backend authorization:
- Token lifetime/purpose/revocation:
- Validation:
- Logging/redaction:

## Integrations and failure handling

Cover email, Kafka, SAP, Sentry, filesystem, and cross-schema behavior where relevant. Define retry/timeout/partial-failure behavior.

## Alternatives considered

| Alternative | Reason accepted/rejected |
|---|---|
| [option] | [reason] |

## Risks and mitigations

| Risk | Likelihood/impact | Mitigation |
|---|---|---|
| [risk] | [rating] | [mitigation] |

## Rollout and rollback

Describe feature flags, deploy order across repositories, migration order, monitoring, and a safe rollback.

