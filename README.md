# Konsolidator

Adapter-based multi-messenger routing library for Elixir.

Unifies the bot APIs of Telegram, Discord, VK, MAX, Matrix, Slack, Microsoft Teams, Google Chat, and others behind a single 12-method behaviour with capability flags. Adapters handle platform-specific formatting; consumers (`Smago`, `SMAXr`, any Elixir bot) just call `Konsolidator.deliver/2`, `Konsolidator.edit/3`, etc.

## Quick start

```elixir
# mix.exs
{:konsolidator, "~> 0.1"},
{:konsolidator_telegram, "~> 0.1"}  # or any other adapter
```

```elixir
# config/config.exs
config :konsolidator, :adapters, [
  Konsolidator.Adapters.Telegram,
  # Konsolidator.Adapters.Discord,
  # Konsolidator.Adapters.VK,
  # Konsolidator.Adapters.MAX,
  # Konsolidator.Adapters.Matrix,
  # Konsolidator.Adapters.Web
]

config :konsolidator, Konsolidator.Adapters.Telegram, token: "123456:ABC-..."
```

```elixir
# anywhere
Konsolidator.deliver(user_id, %Konsolidator.Content{
  text: "Hello, world!",
  buttons: [[%Konsolidator.Button{label: "Click me", data: "click:1"}]]
})
```

## Documentation

- 12-method common API surface — see `Konsolidator.Adapter`
- Content & Button types — see `Konsolidator.Content`, `Konsolidator.Button`
- Capability flags — see `Konsolidator.Capabilities`
- Built-in adapters — see `Konsolidator.Adapters.Telegram` (and the others)
- Contract test macros — see `Konsolidator.Contract`

## License

MIT.
