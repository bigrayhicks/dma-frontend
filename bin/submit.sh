#!/bin/bash

CUCKOO_API_URL=("http://crgb:8090" "http://crg:8090")
CUCKOO_API_TASKS_CREATE_FILE="/tasks/create/file"
CUCKOO_API_TASKS_VIEW="/tasks/view/"
CUCKOO_STATUS="/cuckoo/status"
CUCKOO_COUNT=`echo ${#CUCKOO_API_URL[@]}`
echo -n "Checking for redis-cli and mutt (want to be in \$PATH) will exit 1 if not found. "
REDISCLI=`which redis-cli` && echo "Got redis-cli continuing…" || exit 1
MUTTCMD=`which mutt` && echo "Got mutt continuing…" || exit 1

GPG_ENABLE=false

ADMINS="circl"

SUBMISSION_MAIL="steve.clement@circl.lu"

# functions
function submitAdmin()
{
    for adminUser in ${ADMINS}
    do
        if [ "${user}" != "$adminUser" ]; then
            $REDISCLI -n 5 SADD t:${adminUser} ${task_id}
        fi
    done
}

function submitMail()
{
    s=`curl ${CUCKOO_API_URL[$1]}${CUCKOO_API_TASKS_VIEW}${task_id} >/tmp/c-$$`
    if [ "$GPG_ENABLE" = true ]; then
        fe=`gpg -e -o /tmp/e-$$.gpg -r ${SUBMISSION_MAIL} ${file}`
        smail=`$MUTTCMD -a /tmp/e-$$.gpg -s "New DMA analysis submitted ${task_id} by ${user}" -- ${SUBMISSION_MAIL} </tmp/c-$$`
        rm /tmp/e-$$.gpg
    else
        smail=`$MUTTCMD -s "New DMA analysis submitted ${task_id} by ${user}" -- ${SUBMISSION_MAIL} < /tmp/c-$$`
    fi
}


function checkAPI()
{
    /bin/sleep 1
    echo "# of cuckoo instances : ${CUCKOO_COUNT}"
    for (( i=0; i<${CUCKOO_COUNT}; i++ ));
    do
        echo "Checking API ${CUCKOO_API_URL[i]}${CUCKOO_STATUS}"
        CUCKOO_VERSION=`curl -s ${CUCKOO_API_URL[i]}${CUCKOO_STATUS} |jq -r .version`
        # Cheap check to see if the cuckoo API is running
        if [ "${CUCKOO_VERSION}" != "" ]; then
            echo "You run cuckoo version ${CUCKOO_VERSION} on cuckoo instance ${i}"
        else
            echo "Could not get cuckoo version from API, perhaps api.py not running?"
            echo "Check API on ${CUCKOO_API_URL[i]}${CUCKOO_STATUS}"
            exit -1
        fi
    done
}

checkAPI

while true
do
    LISTSIZE=$($REDISCLI -n 5 LLEN submit)
    START=0
    if [ "${LISTSIZE}" != 0 ]; then
        echo ${LISTSIZE}
    fi
    for (( c=1; c<=$LISTSIZE; c++ ))
    do
        VAL=$($REDISCLI -n 5 LPOP submit)
        user=`echo "${VAL}" |  cut -f1 -d:`
        file=`echo "${VAL}" |  cut -f2 -d:`
        machine=`echo "${VAL}" |  cut -f3 -d:`
        package=`echo "${VAL}" |  cut -f4 -d:`
        echo "username              : ${user}"
        echo "file                  : ${file}"
        echo "machine               : ${machine}"
        echo "package               : ${package}"
        echo "# of cuckoo instances : ${CUCKOO_COUNT}"
        for (( i=0; i<${CUCKOO_COUNT}; i++ ));
        do
        # xargs is used to trim any leading spaces
        if [ "$CUCKOO_VERSION" == "2.0-dev" ]; then
            task_id=`curl -F package=${package} -F machine=${machine} -F file=@${file} ${CUCKOO_API_URL[i]}${CUCKOO_API_TASKS_CREATE_FILE} | jq -r .task_id | grep '[0-9]' |xargs`
            status=$($REDISCLI -n 5 SADD t:${user}:HEAD ${task_id})
            echo "task_id ${task_id}"
            submitAdmin
            submitMail $i
        elif [ "$CUCKOO_VERSION" = "1.3-Optiv" ] || [ "$CUCKOO_VERSION" = "1.3-NG" ]; then
            task_id=`curl -F package=${package} -F machine=${machine} -F file=@${file} ${CUCKOO_API_URL[i]}${CUCKOO_API_TASKS_CREATE_FILE} | jq -r .task_ids | grep '[0-9]' |xargs`
            echo "task_id ${task_id}"
            status=$($REDISCLI -n 5 SADD t:${user}:modified ${task_id})
            submitAdmin
            submitMail $i
        fi
        done
    done
    sleep 10
done
