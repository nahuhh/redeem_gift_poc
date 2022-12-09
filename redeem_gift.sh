#!/bin/bash

# TODO auto Generate the monero_wallet: from an open wallet (get_transfers in/out)
# data saved in your 'redeem gift card app / wallet'
node="node2.monerodevs.org:38089/json_rpc"
rpc_binary="./monero-wallet-rpc --stagenet"
# Prompt for scanning method
echo 'How would you like to scan your Gift Card?'
scan_uri="USER INPUT"
read -p "NFC,QR CODE,PASTE [N/P/Q]: " scan_uri
if   [[ $scan_uri == n* || $scan_uri == N* ]]
	then echo 'Tap the Gift Card'
	monero_uri=$(termux-nfc -r short | jq -r .Record.Payload)
elif [[ $scan_uri == p* || $scan_uri == P* ]]
	then echo 'Paste the URI'
	monero_uri="USER INPUT"
	read -p "URI: " monero_uri
elif [[ $scan_uri == q* || $scan_uri == Q* ]]
	then echo 'BinaryEye will open. Make sure to copy the scan result'
	read -p "Press enter to continue"
	am start --user 0 -n de.markusfisch.android.binaryeye/.activity.CameraActivity
	monero_uri="USER INPUT"
	read -p "Paste QR Results: " monero_uri
else
	echo Try again.
	exit 0
fi

# prompt for destination address
echo 'How would you like to enter your destination address?'
scan_wallet="USER INPUT"
read -p "NFC,QR CODE,PASTE [N/P/Q]: " scan_wallet
if   [[ $scan_wallet == n* || $scan_wallet == N* ]]
	then echo 'Tap to scan'
	pay_to_address=$(termux-nfc -r short | jq -r .Record.Payload)
elif [[ $scan_wallet == p* || $scan_wallet == P* ]]
	then echo 'Paste your personal wallet address'
	pay_to_address="USER INPUT"
	read -p "Wallet address: " pay_to_address
elif [[ $scan_wallet == q* || $scan_wallet == Q* ]]
	then echo 'BinaryEye will open. Make sure to copy the scan result'
	read -p "Press enter to continue"
	am start --user 0 -n de.markusfisch.android.binaryeye/.activity.CameraActivity
	pay_to_address="USER INPUT"
	read -p "Paste QR Results: " pay_to_address
else
	echo Try again.
	exit 0
fi

# basic sanity check for qr and nfc
if [[ $scan_wallet != p* || $scan_wallet != P* ]]; then
IFS=':' read -ra ADDR <<< "$pay_to_address"
	if [[ ${ADDR[0]} != "monero" ]]; then
        echo "Not a 'monero:' wallet uri";
        exit 0
	fi
fi

pay_to_address=$(echo $pay_to_address | sed "s/"monero:"/""/g")
printf "\n$pay_to_address\n"
conf_addr="USER INPUT"
read -p "Does the above address look correct? [Y/N]:" conf_addr
if [[ $conf_addr == y* || $conf_addr == Y* ]]; then
	echo 'Address Confirmed'
	else
	echo "Restore Aborted."
	exit 0
fi

# basic sanity checks
IFS=':' read -ra ADDR <<< "$monero_uri"
if [[ ${ADDR[0]} != "monero_wallet" ]]; then
	echo "Not a 'monero_wallet:' uri";
	exit 0
fi

generate_from_seed=0
view_key=""
spend_key=""
txid=""
address=""
seed=""

IFS='&' read -ra params <<< ${ADDR[1]}
for chunk in "${params[@]}"; do
	IFS='=' read -ra value <<< $chunk
	if [[ "${value[0]}" == "spend_key" ]]; then
		spend_key="${value[1]}"
	fi
	if [[ "${value[0]}" == "view_key" ]]; then
		view_key="${value[1]}"
	fi
	if [[ "${value[0]}" == "txid" ]]; then
		txid="${value[1]}"
	fi
	if [[ "${value[0]}" == "address" ]]; then
		address="${value[1]}"
	fi
	if [[ "${value[0]}" == "seed" ]]; then
		seed="${value[1]}"
	fi
done

printf "params from uri:\n"
printf "view_key:\n$view_key\n"
printf "spend_key:\n$spend_key\n"
printf "txid list:\n$txid\n"
printf "your address:\n$pay_to_address\n"
#printf "seed:\n'$seed'\n"

# confirm 4 requirements (address/spend/view/txids) or (seed/txids)
if [[ ! "$txid" ]]; then
	echo "no txids to scan"; exit 0
elif [[ "$seed" ]]; then
	generate_from_seed=1
elif [[ "$view_key" && "$spend_key" && "$address" ]]; then
	:
else
	echo "minimum [seed+txid] needed to redeem. or [address+viewkey+spendkey+txid]"; exit 0
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
spam=0
while [[ -z "$status" ]]
do
	sleep 1
	if [[ $spam == 3 ]]; then printf "\nRPC not available yet..."; spam=0; fi ; ((spam++))
	status=$(curl -sk http://localhost:18082/json_rpc -d '{"jsonrpc":"2.0","id":"0","method":"stop_wallet"}' -H 'Content-Type: application/json')
done

echo
rm redeem_gift
rm redeem_gift.keys

if [[ $generate_from_seed == 1 ]]; then
	seed=$(echo $seed | sed 's/%20/ /g')
	resp_generate=$(curl -sk http://localhost:18082/json_rpc -d "{\"jsonrpc\":\"2.0\",\"id\":\"0\",\"method\":\"restore_deterministic_wallet\",\"params\":{\"seed\":\"${seed}\",\"restore_height\":${HEIGHT},\"filename\":\"redeem_gift\",\"password\":\"\"}}" -H 'Content-Type: application/json')
else
	resp_generate=$(curl -sk http://localhost:18082/json_rpc -d "{\"jsonrpc\":\"2.0\",\"id\":\"0\",\"method\":\"generate_from_keys\",\"params\":{\"address\":\"${address}\",\"restore_height\":${HEIGHT},\"filename\":\"redeem_gift\",\"spendkey\":\"${spend_key}\",\"viewkey\":\"${view_key}\",\"password\":\"\"}}" -H 'Content-Type: application/json')
fi
# todo check if error returned then exit

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
exit 0
