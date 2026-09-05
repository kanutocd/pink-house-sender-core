## [Unreleased]

### Added

- Provider-neutral message, delivery, capability, delivery-event, and
  normalized-error contracts.
- Provider configuration, lazy loading, deterministic election, bounded
  failover, circuit protection, health tracking, and attempt history.
- Replaceable process-local state and structured observability primitives.
- Standard-library HTTP transport with configurable timeouts and normalized
  network and timeout errors.
- A documented state-store contract with atomic updates and deterministic,
  backend-serializable keys.
- Redis-backed shared state with namespaced JSON values, configurable TTLs,
  optimistic transactions, and normalized backend errors.
- Serializable circuit-breaker and health snapshots that can be persisted and
  rehydrated by the router.

### Quality

- Focused unit and reusable state-store contract tests, including concurrent
  update and runtime snapshot compatibility coverage.
- An opt-in real-Redis integration test for concurrent atomic updates.
- RBS signatures and channel-independent defaults.
- The `bundle exec rake` quality harness covering tests, RuboCop, RBS, and
  100% YARD documentation coverage.
