# Konsolidator

Adapter-based multi-messenger routing library for Elixir.

## Status

- ✅ Core data types (`Content`, `Button`, `Capabilities`)
- ✅ `Konsolidator.Adapter` behaviour (8 callbacks)
- ✅ `Konsolidator.Router` (Phoenix.PubSub-backed)
- ✅ `Konsolidator.Registry` (per-user, per-channel adapter tracking)
- ✅ `Konsolidator.Supervisor` and `Konsolidator.Application`
- ✅ Telegram adapter (`Konsolidator.Adapters.Telegram`) — long-poll, send/edit/delete/typing, markdown→HTML, inline buttons
- 🚧 Contract test macro (`Konsolidator.Contract`)
- 🚧 Real-bot smoke test

## Running

```bash
mix deps.get
mix compile
mix test
```

## Using with a real Telegram bot

```elixir
# config/config.exs
config :konsolidator, :adapters, [Konsolidator.Adapters.Telegram]
config :konsolidator, Konsolidator.Adapters.Telegram, token: "123456:ABC..."
```

```elixir
# anywhere
{:ok, ref} = Konsolidator.Adapters.Telegram.send(
  Konsolidator.Adapters.Telegram,
  chat_id,
  %Konsolidator.Content{text: "Hello!", parse_mode: :markdown}
)
```
