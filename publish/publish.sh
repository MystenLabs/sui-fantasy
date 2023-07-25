#!/bin/bash

# check dependencies are available.
for i in jq curl sui; do
  if ! command -V ${i} 2>/dev/null; then
    echo "${i} is not installed"
    exit 1
  fi
done

NETWORK=http://localhost:9000
ORACLE_ID="0xb2cbc8fc36cf0d1aaad2daf2e153695179051aa746998ec57b8a781a64f775c6"

if [ $# -ne 0 ]; then
  if [ $1 = "devnet" ]; then
    NETWORK="https://fullnode.devnet.sui.io:443"
  fi
  if [ $1 = "testnet" ]; then
    NETWORK="http://dfw-exp-val-00.experiments.sui.io:9000"
    # NETWORK="https://fullnode.testnet.sui.io:443"
  fi
  if [ $1 = "mainnet" ]; then
    NETWORK="https://fullnode.mainnet.sui.io:443"
  fi
fi

echo "- Admin Address is: ${ADMIN_ADDRESS}"

import_address=$(sui keytool import "$ADMIN_PHRASE" ed25519)

switch_res=$(sui client switch --address ${ADMIN_ADDRESS})

ACTIVE_ADMIN_ADDRESS=$(sui client active-address)
echo "Admin address used for publishing: ${ACTIVE_ADMIN_ADDRESS}"
ACTIVE_NETWORK=$(sui client active-env)
echo "Environment used is: ${ACTIVE_NETWORK}"

publish_res=$(sui client publish --gas-budget 2000000000 --json ../move)

echo ${publish_res} >.publish.res.json

# Check if the command succeeded (exit status 0)
if [[ "$publish_res" =~ "error" ]]; then
  # If yes, print the error message and exit the script
  echo "Error during move contract publishing.  Details : $publish_res"
  exit 1
fi

PACKAGE_ID=$(echo "${publish_res}" | jq -r '.effects.created[] | select(.owner == "Immutable").reference.objectId')

newObjs=$(echo "$publish_res" | jq -r '.objectChanges[] | select(.type == "created")')

REGISTRY_ID=$(echo "$newObjs" | jq -r 'select (.objectType | contains("::fantasy_wallet::Registry")).objectId')

# WEATHER_ORACLE_ID=$(echo "$newObjs" | jq -r 'select (.objectType | contains("::weather::WeatherOracle")).objectId')

PUBLISHER_ID=$(echo "$newObjs" | jq -r 'select (.objectType | contains("package::Publisher")).objectId')

UPGRADE_CAP_ID=$(echo "$newObjs" | jq -r 'select (.objectType | contains("package::UpgradeCap")).objectId')

suffix=""
if [ $# -eq 0 ]; then
  suffix=".localnet"
fi

cat >../sui-fantasy/.env<<-ENV
FULLNODE=$NETWORK
ADMIN_PHRASE=$ADMIN_PHRASE
PACKAGE_ID=$PACKAGE_ID
REGISTRY_ID=$REGISTRY_ID
ORACLE_ID=$ORACLE_ID
PUBLISHER_ID=$PUBLISHER_ID
UPGRADE_CAP_ID=$UPGRADE_CAP_ID
ADMIN_ADDRESS=$ACTIVE_ADMIN_ADDRESS
ACTIVE_NETWORK=$ACTIVE_NETWORK
ENV

echo "Sui Fantasy Contracts Deployment finished!"

