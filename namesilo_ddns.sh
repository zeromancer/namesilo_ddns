#!/bin/bash
#set -x ## Print all executed commands to the terminal
set -e ## Exit immediately if a command exits with a non-zero status

#
# Parse arguments
#
function show_usage() {
	echo -e "Usage: $0 domain (optional subdomain)"
	echo "example: $0 example.com"
	echo "example: $0 example.com mysubdomain"
}

if [[ $# -lt 1 || $# -gt 2 ]] ; then
	show_usage
	exit 0
fi

DOMAIN="$1"
SUBDOMAIN="$2"

#
# Load API Key from file
#
SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
API_KEY_FILE=$(echo "$SCRIPTPATH"/namesilo_api.key)
API_KEY_MISSING="YOUR_API_KEY"
API_KEY_CONTENT=""

function show_missing_api_key() {
	echo "Write your api key into $API_KEY_FILE"
	echo "	If you do not know your API Key get it here: https://www.namesilo.com/account_api.php"
}
if [[ ( -f "$API_KEY_FILE" ) && ( -r "$API_KEY_FILE" ) ]] ; then
	API_KEY_CONTENT=$(cat $API_KEY_FILE)
else
	show_missing_api_key
	echo "$API_KEY_MISSING" > $API_KEY_FILE
	exit 0
fi
if [[ ( -z "$API_KEY_CONTENT" ) || ( "$API_KEY_CONTENT" == "$API_KEY_MISSING" ) ]]; then
	show_missing_api_key
	exit 0
fi

APIKEY=$API_KEY_CONTENT

## myhost.mydomain.ltd vs mydomain.ltd
RECORD_NAME=$([[ -z "$SUBDOMAIN" ]] && echo $DOMAIN || echo $SUBDOMAIN.$DOMAIN)

## Saved history pubic IP from last check
IP_FILE="/var/tmp/namesilo_ddns-ip-$RECORD_NAME.txt"
## Response from Namesilo
LIST_RESPONSE="/tmp/namesilo_ddns-list-$RECORD_NAME.xml"
UPDATE_RESPONSE="/tmp/namesilo_ddns-update-$RECORD_NAME.xml"

## Choose randomly which OpenDNS resolver to use
RESOLVER=resolver$(echo $((($RANDOM%4)+1))).opendns.com
## Get the current public IP using DNS
CUR_IP="$(dig +short myip.opendns.com @$RESOLVER)"
ODRC=$?

## Try google dns if opendns failed
if [ $ODRC -ne 0 ]; then
	 logger -t IP.Check -- IP Lookup at $RESOLVER failed!
	 sleep 5
## Choose randomly which Google resolver to use
	 RESOLVER=ns$(echo $((($RANDOM%4)+1))).google.com
## Get the current public IP 
	 IPQUOTED=$(dig TXT +short o-o.myaddr.l.google.com @$RESOLVER)
	 GORC=$?
## Exit if google failed
	 if [ $GORC -ne 0 ]; then
		 logger -t IP.Check -- IP Lookup at $RESOLVER failed as well!
		 exit 1
	 fi
	 CUR_IP=$(echo $IPQUOTED | awk -F'"' '{ print $2}')
fi

##Check file for previous IP address
if [ -f $IP_FILE ]; then
	KNOWN_IP=$(cat $IP_FILE)
else
	KNOWN_IP=
fi

## Logic:
##	3 IPs: 
##		KNOWN_IP - saved on file,
##		CUR_IP = dns lookup, 
##		REMOTE_IP = from api
## if KNOWN_IP == CUR_IP -> nothing to do -> exit
## if KNOWN_IP != CUR_IP -> KNOWN_IP=CUR_IP
## if REMOTE_IP != CUR_IP -> try updating with api
##	 if success -> update check time
##	 if failure -> restore old KNOWN_IP (-> will recheck next time/run)


if [ "$CUR_IP" == "$KNOWN_IP" ]; then
	## No change in IP -> nothing to do -> exit
	exit 0
fi

## See if the IP has changed
logger -t IP.Check -- Public IP changed to $CUR_IP from $RESOLVER

## Get DNS records from Namesilo:
LIST_RESPONSE=$(lexicon namesilo --auth-token e1dabb26c2a7fd8383cae1 list infm.space A | grep list_records | sed 's/list_records: //' )
## Get Namesilo IP
REMOTE_IP=$(echo $LIST_RESPONSE | sed "s/[']/\"/g" | jq -M ".[] | select(.name==\"$RECORD_NAME\") | .content" | sed 's/["]//g' )
## Get Record ID to update with API (needed to change it)
RECORD_ID=$(echo $LIST_RESPONSE | sed "s/[']/\"/g" | jq -M ".[] | select(.name==\"$RECORD_NAME\") | .id" | sed 's/["]//g' )

if [[ "$CUR_IP" == "$REMOTE_IP" ]]; then
	logger -t IP.Check -- Namesilo was correctly set but other dns are lagging behind. No update necessary
	exit 0
fi

logger -t IP.Check -- Calling API to update ip from $REMOTE_IP to $CUR_IP
curl -s "https://www.namesilo.com/api/dnsUpdateRecord?version=1&type=xml&key=$APIKEY&domain=$DOMAIN&rrid=$RECORD_ID&rrhost=$SUBDOMAIN&rrvalue=$CUR_IP&rrttl=7207" > $UPDATE_RESPONSE
RESPONSE_CODE=$(xmllint --xpath "//namesilo/reply/code/text()"	$UPDATE_RESPONSE)

if [[ $RESPONSE_CODE == 300 ]]; then
	logger -t IP.Check -- DDNS Update = SUCCESS. Now $RECORD_NAME IP set to $CUR_IP
	echo "$CUR_IP" > "$IP_FILE"
elif [[ $RESPONSE_CODE == 280 ]]; then
	logger -t IP.Check -- DDNS Update = DUPLICATE. No update necessary
	echo "$CUR_IP" > "$IP_FILE"
else
	## Put the old IP back, so that the update will be tried next time
	echo $KNOWN_IP > $IP_FILE
	logger -t IP.Check -- DDNS Update = FAILED. Response code $RESPONSE_CODE!
fi
exit 0
