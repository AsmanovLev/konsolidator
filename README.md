# Konsolidator

Elixir client library for multi-messenger integrations (Telegram, Discord, VK, MAX, Matrix, Slack, ...). One `Konsolidator.Adapter` behaviour, one `Konsolidator.Router` for incoming events, one facade to send to any backend.

## Status

Stable. Telegram adapter implemented and tested with real API smoke. See `STATUS.md` for the full feature matrix.

## Usage

```elixir
# In your application.ex
config :konsolidator, :adapters, [Konsolidator.Adapters.Telegram]

config :konsolidator, Konsolidator.Adapters.Telegram,
  token: System.get_env("TELEGRAM_BOT_TOKEN"),
  long_poll_timeout: 30

# Send a message
Konsolidator.send(chat_id, %{text: "Hello!", parse_mode: :html})

# Receive incoming events
Konsolidator.Router.subscribe_incoming()
```

## Installation

In `mix.exs`:

```elixir
def deps do
  [
    {:konsolidator, "~> 0.1", path: "deps/konsolidator"}
  ]
end
```

Or via Hex (when published):

```elixir
{:konsolidator, "~> 0.1"}
```

## Running

```bash
mix deps.get
mix test        # 69 tests
mix run         # boot the application
```

## Adapters

| Backend  | Status      | Notes                          |
|----------|-------------|--------------------------------|
| Telegram | ✅ Stable   | Long-poll, SOCKS5 via curl     |
| Discord  | 🚧 Planned  |                                |
| VK       | 🚧 Planned  |                                |
| MAX      | 🚧 Planned  |                                |
| Matrix   | 🚧 Planned  |                                |
| Slack    | 🚧 Planned  |                                |

## License

MIT.
