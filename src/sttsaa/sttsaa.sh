#!/bin/bash

### variables
who=$(whoami)
hDir="/home/${who}/scripts/sttsaa"
source "${hDir}/sttsaa.conf"

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
                        echo ${2} >> ${LogFile}
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

function fnCulrCheck()
{
    curl \
    -s \
    -o /dev/null \
    -w "%{http_code}" \
    ${1}
}

function fnQuery()
{
    "${1}" query wasm contract-store \
    "${2}" \
    "${3}" \
    --height "${4}" \
    -o json
}

function fnSed()
{
    ### replace " " to new line
    sed -i "s/\\\" \"/\\n/g" ${1}
    ### remove "
    sed -i "s/\\\"//g" ${1}
    ### replace spaces to comas
    sed -i "s/\\ /\,/g" ${1}
    ### remove empty lines
    sed -i "/^$/d" ${1}
}
function fnRmDir()
{
    ### clean tmp directory
    if [[ -d "${1}" ]]
    then
        rm "${1}"/* 2>/dev/null
    else
        fnError "DirNoExist" "${1}"
    fi
}

function fnSttUni()
{
    ### check source file
    if [[ ! -e "${1}" ]]
    then
            fnError "SrcFlNoExist" "${1}"

    elif [[ ! -s "${1}" ]]
    then
            fnError "EmptyFl" "${1}"
    fi

    ### clear tmp file
    > "${2}"

    ### loop for readling all contracts
    while IFS=',' read -r cName cAddress; do

       if [ -z "${cName}" ] || [ -z "${cAddress}" ]
        then
            fnError "Empty" "${1}"

        else
            ### loop variables
            local aDr=0
            local MsgQuery="${3}"

            echo Stt: "${cName}"

            ### query first block
            jOut=$(fnQuery "${terrad}" "${cAddress}" "${MsgQuery}" "${7}")
            if [ $? -ne 0 ]; then
                sleep 5
                jOut=$(fnQuery "${terrad}" "${cAddress}" "${MsgQuery}" "${7}")
                if [ $? -ne 0 ]; then
                    sleep 5
                    jOut=$(fnQuery "${terrad}" "${cAddress}" "${MsgQuery}" "${7}")
                    if [ $? -ne 0 ]; then
                        fnError "TerraQuery" "${jOut}"
                    fi
                fi
            fi

            while [ "${aDr}" != "null" ]; do

                ### address of last staker
                local aDr=$(echo "${jOut}" | jq "${4}")
                local MsgQuery="${5}:${aDr}}}"

                ### filter requested data to file
                echo "${jOut}" | jq "${6}" >> "${2}"

                echo address: "$aDr"

                ### query next blocks
                jOut=$(fnQuery "${terrad}" "${cAddress}" "${MsgQuery}" "${7}")
                if [ $? -ne 0 ]; then
                    sleep 5
                    jOut=$(fnQuery "${terrad}" "${cAddress}" "${MsgQuery}" "${7}")
                    if [ $? -ne 0 ]; then
                        sleep 5
                        jOut=$(fnQuery "${terrad}" "${cAddress}" "${MsgQuery}" "${7}")
                        if [ $? -ne 0 ]; then
                            fnError "TerraQuery" "${jOut}"
                        fi
                    fi
                fi

            done

        fi

    done < "${1}"

    ### prepare csv file
    fnSed "${2}"

    ### remov duplicate entries
    sort -u -o "${2}"{,}

}

function fnCheckBlock()
{
    local tStatus=$(${terrad} status |jq "${1}"|tr -d '"')
    local bNumber=$(echo "${tStatus}" | cut -d" " -f 1)

    ### substract some blocks (50)
    local bNumber=$((${bNumber} - ${sValue}))
    local bDate=$(date -d $(echo "${tStatus}" | cut -d" " -f 2) +%s)

    ### date comparision
    if [ "$bDate" -ge "$twoHoursAgo" ];
    then
        echo "${bNumber}"
    else
        fnError "WrongDate"
    fi

}

function fnMain()
{

    local jQuerySI=".SyncInfo| \"\(.latest_block_height) \(.latest_block_time)\""

    ### find current block number
    Block=$(fnCheckBlock "${jQuerySI}")

    local SttSaaFile="${hDir}/${tDir}/STTSAA_${Block}.csv"
    local MsgQuery="{\"stakers_info\":{\"limit\":30}}"
    local jQuery=".query_result.stakers[-1].staker"
    local MsgQuery2="{\"stakers_info\":{\"limit\":30,\"start_after\""
    local jQuery2=".query_result.stakers[] | \"\\(.staker) \\(.bond_amount)\""
    local jCont="${hDir}/${tDir}/tmp.json"
    local uFile="STTSAA_${Block}.csv"
    local outFile="${tRepo}/${uFile}"

    fnSttUni "${sttSaaContract}" "${SttSaaFile}" "${MsgQuery}" "${jQuery}" "${MsgQuery2}" "${jQuery2}" "${Block}"

    echo "STTSAA end"

    ### prepare content for curl command
    fnPrepFile "${SttSaaFile}" "${outFile}" "${uFile}" "${Msg}" "${Branch}" "${jCont}"

    ### upload temporary file to GitHub
    fnUpdateRepo "${aToken}" "${jCont}" "${outFile}"

    echo "Repo ${uFile} finally updated!"

    ### clean tmp directory
    fnRmDir "${hDir}/${tDir}"

}

fnMain
