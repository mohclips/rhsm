#!/bin/bash
#set -x
# https://access.redhat.com/articles/3626371#comment-1622371

# Subscriptions to check
SUBS=(6507358 7714792)

RHN_ACCOUNT=5573408

WHITELIST=(del-boy.localdomain Golden-AMI test-from-image mgmt2.test.mcwm.local testclient2.test.local)
#WHITELIST=(Golden-AMI test-from-image)

EMAIL_TO=nicholas.cross@uk.fujitsu.com

# get a token here
# https://access.redhat.com/management/api
SCRIPT_PATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
cd $SCRIPT_PATH
. ./offline_token.sh

function jsonValue() {
KEY=$1                                            
num=$2
awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'$KEY'\042/){print $(i+1)}}}' | tr -d '"' | sed -n ${num}p
}

TIMEOUT="--connect-timeout 2 --max-time 10"

# create online token
TOKEN=`curl -s $TIMEOUT https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token -d grant_type=refresh_token -d client_id=rhsm-api -d refresh_token=$OFFLINE_TOKEN | jsonValue access_token`

if [[ "${TOKEN}x" == "x" ]] ; then
	echo "Can't create token"
	echo $TOKEN
	exit 1
fi

for SUB in ${SUBS[@]}; do

    DATA=$(curl -s $TIMEOUT -X GET \
        -H "accept: application/json" \
        -H "Authorization: Bearer $TOKEN" \
        "https://api.access.redhat.com/management/v1/subscriptions/$SUB/systems" )

    if [[ "${DATA}x" == "x" ]] ; then
	echo "No data from RHSM"
	echo $DATA
	exit 2
    fi

    if [[ ${DATA} =~ "An error occurred" ]] ; then
	echo $DATA
	echo "Error from RHSM"
	exit 3
    fi

    if ! [[ ${DATA} =~ "pagination" ]] ; then
	echo "Error from RHSM missing fields"
	echo $DATA
	exit 4
    fi

    #echo data:$DATA

# {
#   "pagination": {
#     "offset": 0,
#     "limit": 100,
#     "count": 1
#   },
#   "body": [
#     {
#       "systemName": "del-boy.localdomain",
#       "uuid": "36ea3dcf-623a-4ad0-aa39-a43096d76a5f",
#       "complianceStatus": "valid",
#       "totalEntitlementQuantity": 1,
#       "type": "Virtual",
#       "lastCheckin": "2019-09-16T12:41:15.000Z"
#     }
#   ]
# }

    while read NAME ID ; do

        if [[ "$NAME" = "" ]] ; then
            continue
        fi

        #echo "Checking $NAME"
        #echo "ID: $ID"

        if printf '%s\n' ${WHITELIST[@]} | grep -q -P '^'$NAME'$'; then
            #echo "Found in whitelist"
            continue
        else
            #echo "Not found in whitelist"

            # get details
            DETAILS=$(curl -s -X GET \
                -H "accept: application/json" \
                -H "Authorization: Bearer $TOKEN" \
                "https://api.access.redhat.com/management/v1/systems/$ID" )

#	    echo $DETAILS 1>&2

    if ! [[ ${DETAILS} =~ "uuid" ]] ; then
	echo "Error from RHSM missing fields"
	echo $DETAILS
	exit 9
    fi

 
            #echo $DETAILS | jq .
# {
#   "body": {
#     "uuid": "36ea3dcf-623a-4ad0-aa39-a43096d76a5f",
#     "name": "del-boy.localdomain",
#     "type": "Virtual",
#     "createdDate": "2018-07-17T10:11:56.000Z",
#     "createdBy": "nicholas.cross@uk.fujitsu.com",
#     "lastCheckin": "2019-09-16T12:41:15.000Z",
#     "installedProductsCount": 1,
#     "entitlementStatus": "valid",
#     "complianceStatus": "Properly Subscribed",
#     "autoAttachSetting": true,
#     "serviceLevelPreference": "",
#     "factsCount": 164,
#     "errataApplicabilityCounts": {
#       "valid": true,
#       "value": {
#         "securityCount": 45,
#         "bugfixCount": 122,
#         "enhancementCount": 12
#       }
#     },
#     "entitlementsAttachedCount": 1
#   }
# }

            read RHN_USERNAME DATED <<<$(  echo $DETAILS | jq -rc '.body | [.createdBy,.createdDate]' | column -t -s'[],"' )


            #
            # mail out
            #

# bash-foo to send a large email :)
(mail -s "Erroneous Subscription in use by $NAME created by $RHN_USERNAME" $EMAIL_TO)<<EOF
Name: $NAME
UUID: $ID
Created By: $RHN_USERNAME
Creation Date: $DATED

Red Hat Account Number: $RHN_ACCOUNT

This has been automatically removed from the $SUB subscription owned by the OptiMISe Project

https://access.redhat.com/management/contracts/11998148/systems  x10
https://access.redhat.com/management/contracts/11944898/systems  x3

Please make sure that you correctly assign your systems to the correct subscriptions/contracts.

As per the email sent to all Fujitsu Employees on the Red Hat Network, dated: 09 July 2019

---
Folks,

We all have a shared account on the RedHat portal. This shared account has contracts and those contracts have subscriptions.    The subscriptions are the way RedHat licence the right to download software and patches.

This means that if you do not allocate your servers properly, as you register them, then you will take subscriptions away from projects (contracts) that require them.  This can be very detrimental to customers and/or projects as they cannot build and register their servers as you have inadvertently taken their licence away from them.


You NEED to register and subscribe your servers correctly, or you will find that your servers will stop getting patches as the owners will remove your subscription from their contract.


For more please read this link: https://access.redhat.com/solutions/253273

This is the important command:
subscription-manager attach --pool=<POOL_ID>

DO NOT "auto-attach" your servers.  This is very bad!!!
subscription-manager attach --auto  # this is bad!
---

Thank you

The OptiMISe Team


EOF

            # remove from contract

            curl -v -X DELETE \
                -H "accept: application/json" \
                -H "Authorization: Bearer $TOKEN" \
                "https://api.access.redhat.com/management/v1/systems/$ID"

        fi


    done <<EOF
$( echo $DATA | jq -rc '.body[] | [.systemName,.uuid]' | column -t -s'[],"' )
EOF

done
