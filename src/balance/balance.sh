#!/bin/bash

### variables
who=$(whoami)
hDir="/home/${who}/scripts/balance"
source "${hDir}/balance.conf"

function fnError()
{
    case ${1} in
        "Empty")        echo "Error reported at $(date) for ${2} has empty values. Please correct, before continuing." >> ${LogFile}
                        exit 1;;
        "EmptyFl")      echo "Error reported at $(date) for ${2}. The file is empty. Please correct, before continuing." >> ${LogFile}
                        exit 1;;
        "SrcFlNoExist") echo "Error reported at $(date) Source file: ${2} does not exist." >> ${LogFile}
                        exit 1;;
        "TerraQuery")   echo "Error reported at $(date). Terrad query is not valid. Adjust command." >> ${LogFile}
                        echo ${jOut} >> ${LogFile}
                        exit 1;;
        "DstFlNoExist") echo "Error reported at $(date). Destination file: ${outFile} does not exist." >> ${LogFile}
                        exit 1;;
        "DirNoExist")   echo "Error reported at $(date) Directory: ${2} does not exist." >> ${LogFile}
                        exit 1;;
        "WrongDate")    echo "Error reported at $(date) Terrad last update was more than 2 hours ago. Please check terrad." >> ${LogFile}
                        exit 1;;
    esac
}

function fnPrepFile()
{
    ### local variables
    local Content="$(openssl base64 -A -in ${1})"
    local Sha="$(curl -X GET ${2} | jq .sha)"

    echo {\"path\": \"${3}\",\
    \"message\": \"${4}\",\
    \"content\": \"${Content}\",\
    \"branch\": \"${5}\",\
    \"sha\": ${Sha}} \
    > ${6}
}

function fnUpdateRepo()
{
    curl \
    -i \
    -s \
    -o /dev/null \
    -X PUT \
    -H "Authorization: token ${1}" \
    -d @${2} \
    ${3}
}

function fnQuery()
{
    ### terrad query
    "${1}" query wasm contract-store \
    "${2}" \
    "${3}" \
    --height "${4}" \
    -o json
}

function fnRmDir()
{
    ### clean tmp directory
    if [[ -d "${1}" ]]; then
        rm "${1}"/* 2>/dev/null
    else
        fnError "DirNoExist" "${1}"
    fi
}

function fnBalance()
{
    ### check source file
    if [[ ! -e "${1}" ]]; then
            fnError "SrcFlNoExist" "${1}"

    elif [[ ! -s "${1}" ]]; then
            fnError "EmptyFl" "${1}"
    fi

    ### loop for readling all contracts
    while IFS=',' read -r cName cAddress cDir; do

       if [ -z "${cName}" ] || [ -z "${cAddress}" ] || [ -z "${cDir}" ]; then
            fnError "Empty" "${1}"

        else
            ### loop variables
            local MsgQuery="${4}:\"${cAddress}\"}}"
            local cFile="${hDir}/${oDir}/${cDir}.csv"
            local jCont="${hDir}/${tDir}/tmp.json"
            local uFile="${cName}_${mDate}.csv"
            local outFile="${7}/${cDir}/${uFile}"

            echo Stt: "${cName}"

            ### try to query block three times, wait 5 seconds between tries
            jOut=$((fnQuery "${2}" "${3}" "${MsgQuery}" "${6}") 2>&1) || \
            sleep 5; \
            jOut=$((fnQuery "${2}" "${3}" "${MsgQuery}" "${6}") 2>&1) || \
            sleep 5; \
            jOut=$((fnQuery "${2}" "${3}" "${MsgQuery}" "${6}") 2>&1)
            if [ $? -ne 0 ]; then
                fnError "TerraQuery"
            fi

            bAmount=$(echo "${jOut}" | jq --raw-output "${5}")
            echo "${fDate},${bAmount}" >> "${cFile}"

            ### prepare content for curl command
            fnPrepFile "${cFile}" "${outFile}" "${uFile}" "${Msg}" "${Branch}" "${jCont}"

            ### upload temporary file to GitHub
            fnUpdateRepo "${aToken}" "${jCont}" "${outFile}"

            echo "Repo ${uFile} finally updated!"

        fi

    done < "${1}"

}

function fnCheckBlock()
{
    local tStatus=$(${1} status |jq "${2}"|tr -d '"')
    local bDate=$(date -d $(echo "${tStatus}" | cut -d" " -f 2) +%s)

    ### date comparision
    if [ "$bDate" -ge "$twoHoursAgo" ]; then
        bNumber=$(echo "${tStatus}" | cut -d" " -f 1)
        mDate=$(date -d $(echo "${tStatus}" | cut -d" " -f 2) +%Y_%b)
        fDate=$(date -d $(echo "${tStatus}" | cut -d" " -f 2) +%Y-%m-%d\ %T)

    else
        fnError "WrongDate"
    fi

}

function fnMain()
{

    local jQuerySI=".SyncInfo| \"\(.latest_block_height) \(.latest_block_time)\""
    local MsgQuery="{\"balance\":{\"address\""
    local jQuery=".query_result.balance"

    ### check block
    fnCheckBlock "${terrad}" "${jQuerySI}"

    ### query balance and send it to git repo
    fnBalance "${bContract}" "${terrad}" "${steGateway}" "${MsgQuery}" "${jQuery}" "${bNumber}" "${tRepo}"

    ### clean tmp directory
    fnRmDir "${hDir}/${tDir}"

}

fnMain
