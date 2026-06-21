import Config

config :konsolidator,
  adapters: [
    # Konsolidator.Adapters.Telegram,
    # Konsolidator.Adapters.Discord,
    # Konsolidator.Adapters.VK,
    # Konsolidator.Adapters.MAX,
    # Konsolidator.Adapters.Matrix,
  ]

# Example for Telegram:
#
# config :konsolidator, Konsolidator.Adapters.Telegram,
#   token: "123456:ABC-DEF...",
#   long_poll_timeout: 30,
#   allowed_updates: ["message", "callback_query"]
