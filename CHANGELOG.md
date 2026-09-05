## [Unreleased]

### Added

- Add immutable provider-neutral message, delivery, capability, delivery-event,
  and normalized-error contracts.
- Add provider configuration and lazy registry primitives for channel gems.
- Add bounded provider election, routing, failover, circuit protection, health
  tracking, and attempt history.
- Add replaceable in-memory state and structured observability primitives.
- Add a standard-library HTTP transport with configurable request timeouts and
  normalized network and timeout errors.
- Add the shared runtime integration boundary used by channel gems such as
  `sms-sender` and `email-sender`.
- Add a documented state-store contract and atomic memory-backend updates for
  future Redis and custom backend implementations.
- Add reusable state-store contract tests and deterministic non-nil key rules.
- Start the Redis state-store backend with namespaced JSON values, TTL support,
  and optimistic atomic updates through an injected Redis client.
- Add serializable circuit-breaker and health snapshots and persist them through
  the router for shared state-store backends.
- Add atomic router state updates and normalized Redis backend errors.

### Quality

- Add focused tests, RBS signatures, and channel-independent defaults.
- Add the `bundle exec rake` quality harness covering tests, RuboCop, RBS, and
  100% YARD documentation coverage.
