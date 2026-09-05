# sender-core

`sender-core` is the channel-neutral Ruby runtime for sender gems such as
[`sms-sender`](https://github.com/kanutocd/sms-sender) and `email-sender`.
It provides reusable delivery contracts, provider selection, failover,
resilience, state, and observability primitives.

## Origin

The sender gems were extracted from the Pink House SaaS project to make its
delivery capabilities reusable, independently testable, and composable across
communication channels. `sender-core` contains the shared runtime extracted
from the original application; channel gems remain responsible for their own
input validation and provider integrations.

Channel gems remain responsible for channel-specific validation, provider
adapters, authentication, payload mapping, and response mapping. The shared
runtime is independent of SMS, email, Rails, Redis, PostgreSQL, provider
SDKs, and live network services.

## Installation

Add the gem to your application's Gemfile:

```ruby
gem "sender-core"
```

Then install it with Bundler:

```bash
bundle install
```

## Architecture

```text
channel facade
      |
sender-core message and delivery contracts
      |
election -> router -> channel provider adapter -> HTTP/provider API
      |
health, circuit breaker, state store, and observability
```

`sender-core` is not a standalone email or SMS client. It supplies the
provider-neutral runtime that channel gems compose into their public APIs.
Provider registries may expose an advisory `support_level` such as
`experimental`, `supported`, `fully_tested`, `deprecated`, or `unsupported`.
This metadata is informational only and never prevents a configured provider
from being used.
Registries also support named instances backed by the same adapter, allowing
multiple accounts to participate independently in priorities, fallback, and
runtime health state.

## Usage

Channel gems normalize their input into a core message, configure one or more
providers, and delegate delivery to the shared router:

```ruby
message = Sender::Core::Message.new(
  to: "recipient@example.test",
  body: "Hello",
  requirements: [:email]
)

delivery = Sender::Core::Router.new(registry: registry).deliver(message)
```

The returned delivery exposes its normalized status, selected provider,
provider message ID, attempt history, and error. Channel-specific validation
and provider request mapping belong in the composing channel gem.

## Development

Install development dependencies with:

```bash
bin/setup
```

Run the complete quality harness with:

```bash
bundle exec rake
```

The harness runs tests, RuboCop, RBS validation, YARD generation, and a 100%
YARD documentation coverage check. Tests must remain deterministic and must
not require credentials, network access, or live provider availability.

Useful individual tasks include:

```bash
bundle exec rake test
bundle exec rake rubocop
bundle exec rake rbs
bundle exec rake yard
bundle exec rake yard:coverage
bundle exec rake build
bin/console
```

## Design principles

- Keep the core channel-neutral and provider-independent.
- Use immutable value objects for delivery context.
- Make retry and failover policy explicit and bounded.
- Keep mutable runtime state behind replaceable abstractions.
- Load providers lazily and keep adapters thin.
- Prefer standard-library boundaries and minimal dependencies.
- Keep live integration checks separate from the default quality gate.

## Contributing

Bug reports and pull requests are welcome at
[github.com/kanutocd/sender-core](https://github.com/kanutocd/sender-core).
Meaningful user, operator, integration, tooling, and architectural changes
should be recorded in `CHANGELOG.md` under `Unreleased`.

## License

This project is available under the [MIT License](LICENSE.txt).

See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for community guidelines.
