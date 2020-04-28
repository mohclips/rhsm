#!/bin/bash

. ./offline_token.sh

#Verify it's set:
#echo $offline_token

#2) Create a function to easily filter out JSON values:
function jsonValue() {
    KEY=$1                                            
    num=$2
    awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'$KEY'\042/){print $(i+1)}}}' | tr -d '"' | sed -n ${num}p
}

#curl -s https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token -d grant_type=refresh_token -d client_id=rhsm-api -d refresh_token=$offline_token

token=$( curl -s https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token -d grant_type=refresh_token -d client_id=rhsm-api -d refresh_token=$offline_token | jsonValue access_token )

#echo $token

curl -H "Authorization: Bearer $token"  "https://api.access.redhat.com/management/v1/systems?limit=100" | jq .

# URL="https://api.access.redhat.com/subscriptions"
# URL=https://api.access.redhat.com/rs/cases
# echo $URL
# curl -s -H "Authorization: Bearer $token" $URL



