#!/bin/sh

# export ACCOUNT_POOL_SIZE=1
export MIX_ENV=prod
export SECRET_KEY_BASE=SbN9xzuWTx5bhEFxDtuaHun0w6xBhlImzoH/GIaNV5A8ADbQ3B7TOLVWWdqR9S/M
export DATABASE_URL=postgresql://postgres:123456@localhost:5432/blockscout
export ETHEREUM_JSONRPC_VARIANT=geth
export ETHEREUM_JSONRPC_HTTP_URL=https://geth.mvm.dev
#export ETHEREUM_JSONRPC_WS_URL=wws://geth.mvm.dev
export BLOCKSCOUT_PROTOCOL=https
export BLOCKSCOUT_HOST=www.hundredark.site
export PORT=4000
export EXCHANGE_RATES_COINGECKO_COIN_ID=ethereum
#export EXCHANGE_RATES_COINGECKO_API_KEY=CONFIGURE_COINGECKO_API_KEY
export BLOCK_TRANSFORMER=base
export DISABLE_READ_API=false
export DISABLE_WRITE_API=true
export INDEXER_MEMORY_LIMIT=12
export ENABLE_TXS_STATS=true
export SHOW_PRICE_CHART=true
export SHOW_TXS_CHART=true
export CACHE_MARKET_HISTORY_PERIOD=300
export GAS_PRICE_ORACLE_NUM_OF_BLOCKS=100
export GAS_PRICE_ORACLE_SAFELOW_PERCENTILE=35
export GAS_PRICE_ORACLE_AVERAGE_PERCENTILE=60
export GAS_PRICE_ORACLE_FAST_PERCENTILE=90
export GAS_PRICE_ORACLE_CACHE_PERIOD=3
export HISTORY_FETCH_INTERVAL=5
export CHAIN_ID=73927
export COIN=ETH
export COIN_NAME=ETH
export NETWORK='Mixin Virtual Machine'
export SUBNETWORK='MVM'
export NETWORK_PATH=/
export WEBAPP_URL=www.hundredark.site
export JSON_RPC=https://geth.mvm.dev
export SUPPORTED_CHAINS='[ { "title": "MVM", "url": "https://scan.mvm.dev" }]'
export LINK_TO_OTHER_EXPLORERS=false
export LOGO=/images/mvm-logo.svg
export LOGO_FOOTER=/images/mvm-logo-footer.svg
export ENABLE_RUST_VERIFICATION_SERVICE=true
export RUST_VERIFICATION_SERVICE_URL=http://0.0.0.0:8043/

mix phx.server 
