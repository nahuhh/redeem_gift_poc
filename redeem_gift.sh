#!/bin/bash
# TODO auto Generate the monero_wallet: from an open wallet (get_transfers in/out)

# data saved in your 'redeem gift card app / wallet'

# Paste destination address and wallet URI
pay_to_address="USER INPUT"
read -p "Destination Address: " pay_to_address

monero_uri="USER INPUT"
read -p "Paste URI: " monero_uri

# Static node for now
node="node2.monerodevs.org:38089/json_rpc"
rpc_binary="./monero-wallet-rpc --stagenet"

#basic sanity checks
IFS=':' read -ra ADDR <<< "$monero_uri"
if [[ ${ADDR[0]} != "monero_wallet" ]];
	then echo "Not a monero_wallet URI";
	exit 0
fi

params_present=0
view_key=""
spend_key=""
txid=""
address=""

IFS='&' read -ra params <<< ${ADDR[1]}
for chunk in "${params[@]}"; do
	IFS='=' read -ra value <<< $chunk
	if [[ "${value[0]}" == "spend_key" ]]; then
		spend_key="${value[1]}"
		((params_present++))
	fi
	if [[ "${value[0]}" == "view_key" ]]; then
		view_key="${value[1]}"
		((params_present++))

	fi
	if [[ "${value[0]}" == "txid" ]]; then
		txid="${value[1]}"
		((params_present++))
	fi
	if [[ "${value[0]}" == "address" ]]; then
		address="${value[1]}"
		((params_present++))
	fi
done

printf "params from uri:\n"
printf "view_key:\n$view_key\n"
printf "spend_key:\n$spend_key\n"
printf "txid list:\n$txid\n"

# confirm 4 requirements (address/spend/view/txids)
if [[ $params_present != 4 ]]; then
	echo "missing view_key/spend_key/txid from uri"; exit 0
fi

# start rpc wallet and hang until its 'available' for rpc commands

REQ=$(curl -sk $node -d '{"jsonrpc":"2.0","id":"0","method":"get_info"}' -H 'Content-Type: application/json')
HEIGHT=$(echo $REQ | jq '.result.height')

$rpc_binary --wallet-dir "$(pwd)" \
--rpc-bind-port 18082 \
--daemon-host $node \
--log-level 0 \
--disable-rpc-login 2>&1 & #outputs rpc into the same terminal window / continues script

status=""
while [[ -z "$status" ]]
do
	printf "\nRPC not available yet..."
	sleep 3
	status=$(curl -sk http://localhost:18082/json_rpc -d '{"jsonrpc":"2.0","id":"0","method":"stop_wallet"}' -H 'Content-Type: application/json')
done

echo
rm redeem_gift
rm redeem_gift.keys

resp_generate=$(curl -sk http://localhost:18082/json_rpc -d "{\"jsonrpc\":\"2.0\",\"id\":\"0\",\"method\":\"generate_from_keys\",\"params\":{\"address\":\"${address}\",\"restore_height\":${HEIGHT},\"filename\":\"redeem_gift\",\"spendkey\":\"${spend_key}\",\"viewkey\":\"${view_key}\",\"password\":\"\"}}" -H 'Content-Type: application/json')
resp_address=$(echo $resp_generate | jq '.result.address')

printf "\nURI Address:\n$address\n"
printf "\nGenerated Address:\n$resp_address\n"

if [[ "$resp_address" != "\"$address\"" ]]; then
	echo "generated address != uri address"; exit 0
fi

WALLET="redeem_gift"
while [[ ! -f "$WALLET" ]]
do
	sleep 1
    printf "\nWait for wallet to be created...\n"
done

curl http://localhost:18082/json_rpc -d '{"jsonrpc":"2.0","id":"0","method":"open_wallet","params":{"filename":"redeem_gift","password":""}}' -H 'Content-Type: application/json'

# parse / scan txs

printf "\nWallet is opened ok\n"
IFS=',' read -ra txids <<< ${txid}
#bash array to string https://stackoverflow.com/a/67489301
txid_list=$(jq --compact-output --null-input '$ARGS.positional' --args -- "${txids[@]}")

#scan_tx accepts our list
curl http://localhost:18082/json_rpc -d "{\"jsonrpc\":\"2.0\",\"id\":\"0\",\"method\":\"scan_tx\",\"params\":{\"txids\":${txid_list}}}" -H 'Content-Type: application/json'
#sweep all to out pay to address
curl http://localhost:18082/json_rpc -d "{\"jsonrpc\":\"2.0\",\"id\":\"0\",\"method\":\"sweep_all\",\"params\":{\"address\":\"${pay_to_address}\",\"do_not_relay\":true}}" -H 'Content-Type: application/json'
#stop wallet at the end
curl http://localhost:18082/json_rpc -d '{"jsonrpc":"2.0","id":"0","method":"stop_wallet"}' -H 'Content-Type: application/json'
