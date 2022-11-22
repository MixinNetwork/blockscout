# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
import Config

network_path =
  "NETWORK_PATH"
  |> System.get_env("/")
  |> (&(if String.ends_with?(&1, "/") do
          String.trim_trailing(&1, "/")
        else
          &1
        end)).()

api_path =
  "API_PATH"
  |> System.get_env("/")
  |> (&(if String.ends_with?(&1, "/") do
          String.trim_trailing(&1, "/")
        else
          &1
        end)).()

# General application configuration
config :block_scout_web,
  namespace: BlockScoutWeb,
  ecto_repos: [Explorer.Repo, Explorer.Repo.Account]

config :block_scout_web,
  admin_panel_enabled: System.get_env("ADMIN_PANEL_ENABLED", "") == "true"

config :block_scout_web, BlockScoutWeb.Counters.BlocksIndexedCounter, enabled: true

config :block_scout_web, BlockScoutWeb.Counters.InternalTransactionsIndexedCounter, enabled: true

# Configures the endpoint
config :block_scout_web, BlockScoutWeb.Endpoint,
  url: [
    path: network_path,
    api_path: api_path
  ],
  render_errors: [view: BlockScoutWeb.ErrorView, accepts: ~w(html json)],
  pubsub_server: BlockScoutWeb.PubSub

config :block_scout_web, BlockScoutWeb.Tracer,
  service: :block_scout_web,
  adapter: SpandexDatadog.Adapter,
  trace_key: :blockscout

# Configures gettext
config :block_scout_web, BlockScoutWeb.Gettext, locales: ~w(en), default_locale: "en"

config :block_scout_web, BlockScoutWeb.SocialMedia,
  twitter: "PoaNetwork",
  telegram: "poa_network",
  facebook: "PoaNetwork",
  instagram: "PoaNetwork"

config :block_scout_web, BlockScoutWeb.Chain.TransactionHistoryChartController,
  # days
  history_size: 30

config :ex_cldr,
  default_locale: "en",
  default_backend: BlockScoutWeb.Cldr

config :logger, :block_scout_web,
  # keep synced with `config/config.exs`
  format: "$dateT$time $metadata[$level] $message\n",
  metadata:
    ~w(application fetcher request_id first_block_number last_block_number missing_block_range_count missing_block_count
       block_number step count error_count shrunk import_id transaction_id)a,
  metadata_filter: [application: :block_scout_web]

config :prometheus, BlockScoutWeb.Prometheus.Instrumenter,
  # override default for Phoenix 1.4 compatibility
  # * `:transport_name` to `:transport`
  # * remove `:vsn`
  channel_join_labels: [:channel, :topic, :transport],
  # override default for Phoenix 1.4 compatibility
  # * `:transport_name` to `:transport`
  # * remove `:vsn`
  channel_receive_labels: [:channel, :topic, :transport, :event]

config :spandex_phoenix, tracer: BlockScoutWeb.Tracer

config :wobserver,
  # return only the local node
  discovery: :none,
  mode: :plug

config :block_scout_web, BlockScoutWeb.ApiRouter,
  writing_enabled: System.get_env("DISABLE_WRITE_API") != "true",
  reading_enabled: System.get_env("DISABLE_READ_API") != "true",
  wobserver_enabled: System.get_env("WOBSERVER_ENABLED") == "true"

config :block_scout_web, BlockScoutWeb.WebRouter, enabled: System.get_env("DISABLE_WEBAPP") != "true"

# Configures Ueberauth local settings
config :ueberauth, Ueberauth,
  providers: [
    auth0: {
      Ueberauth.Strategy.Auth0,
      [callback_path: "/auth/auth0/callback"]
    }
  ]

config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 4, cleanup_interval_ms: 60_000 * 10]}

config :block_scout_web, BlockScoutWeb.API.RPC.AddressController,
  mvm_default_assets: [
    "0x0e42ae5649b3a67842af0f3fc21d09d9b850a694", # BTC
    "0xe968257b324264858c0704fcd260d6673d7fe5cf", # EOS
    "0x034a771797a1c8694bc33e1aa89f51d1f828e5a4", # XIN
    "0xc39cb12df2ab413d4f3d1a2212a09bbf98ff650e", # TRX
    "0x59e0f2e9254db4d662ef36a02118ec5dbd9f8dfb", # USDT
    "0xac2ac36102f96f1fded2724f1d54b9fca6bbf1ee", # USDT
    "0x4c29a2ae22453cbfab915083ea9bcbff424cea4d", # DOGE
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
