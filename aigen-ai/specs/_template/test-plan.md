# Test plan — [feature or fix]

## Acceptance-criteria mapping

| Acceptance criterion | Test/verification | Level | Repository/file | Expected result | Status |
|---|---|---|---|---|---|
| AC-1 | [test name/steps] | Unit/API/UI/manual | [path] | [result] | Planned |

Every acceptance criterion must appear at least once.

## Automated coverage

### Backend

- Test files:
- Mocks/fixtures:
- Command:

### Frontend

- Test files/harness:
- Command:
- If no harness is introduced, explain the approved manual substitute.

### Import worker

- Test files/harness:
- Transaction/idempotency cases:
- Command:
- Never use a real worker run as a test.

## Contract and integration checks

- HTTP/OpenAPI:
- Kafka/command:
- Database migration/rollback:
- Cross-repository compatibility:

## Manual scenarios

| Scenario | Preconditions/test data | Steps | Expected result |
|---|---|---|---|
| [scenario] | [safe non-production data] | [steps] | [result] |

## Security and failure cases

- Unauthorized/forbidden role:
- Missing/expired/revoked token:
- Invalid input:
- Dependency timeout/failure:
- Duplicate/retry/concurrent request:
- Partial database/integration failure:

## Commands and results

| Command | Date | Result | Notes |
|---|---|---|---|
| [exact command] | [date] | Pass/Fail/Blocked | [details] |

## Unverified behavior

List everything that could not be verified and why.

