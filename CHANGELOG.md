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

### Quality

- Add focused tests, RBS signatures, and channel-independent defaults.
- Add the `bundle exec rake` quality harness covering tests, RuboCop, RBS, and
  100% YARD documentation coverage.
