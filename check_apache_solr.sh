#!/bin/bash
#
# check_apache_solr.sh is a bash function to check Apache Solr
# Copyright (C) 2023 Ramon Roman Castro <ramonromancastro@gmail.com>
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see http://www.gnu.org/licenses/.
#
# @package    nagios-plugins
# @author     Ramon Roman Castro <ramonromancastro@gmail.com>
# @link       http://www.rrc2software.com
# @link       https://github.com/ramonromancastro/nagios-plugins

SOLR_HOST=localhost
SOLR_PORT=8983
SOLR_USER=
SOLR_PASSWD=
SOLR_CORE=
SOLR_SSL=0
SOLR_PERF=0
SOLR_WARNING=
SOLR_CRITICAL=
SOLR_CHECK=

VERSION='0.3'

NAGIOS_OK=0
NAGIOS_WARNING=1
NAGIOS_CRITICAL=2
NAGIOS_UNKNOWN=3

NAGIOS_STATUS=$NAGIOS_OK
NAGIOS_MESSAGE='OK - All cores are ok'
NAGIOS_DETAILS=()
NAGIOS_PERF=()

SOLR_CORE_FOUND=0

set_nagios_status(){
    status=$1
    if [[ $status == $NAGIOS_CRITICAL ]]; then
        NAGIOS_STATUS=$status
    elif [[ $status == $NAGIOS_WARNING && $NAGIOS_STATUS != $NAGIOS_CRITICAL ]]; then
        NAGIOS_STATUS=$status
    elif [[ $status == $NAGIOS_UNKNOWN && $NAGIOS_STATUS != $NAGIOS_CRITICAL && $NAGIOS_STATUS != $NAGIOS_WARNING ]]; then
        NAGIOS_STATUS=$status
    else
        NAGIOS_STATUS=$status
    fi
}

nagios_exit(){
    echo $NAGIOS_MESSAGE
    if [ ${#NAGIOS_DETAILS[@]} -gt 0 ]; then
        for i in ${!NAGIOS_DETAILS[*]};do
            echo ${NAGIOS_DETAILS[$i]}
        done
    fi
    if [[ ${#NAGIOS_PERF[@]} -gt 0 && $SOLR_PERF -eq 1 ]]; then
        echo -n "|"
        for i in ${!NAGIOS_PERF[*]};do
            echo -n "${NAGIOS_PERF[$i]} "
        done
    fi
    exit $NAGIOS_STATUS
}

check_cores(){
    core_info=$(solr_request "admin/cores?action=STATUS&wt=json")
    check_request "${core_info}"
    cores=($(echo ${core_info} | jq -r '.status | keys | .[]'))

    if [ ! -z $SOLR_CORE ]; then
        for i in "${cores[@]}"
        do
            if [ $SOLR_CORE == ${i} ]; then
                SOLR_CORE_FOUND=1
            fi
        done
    fi

    if [[ ! -z $SOLR_CORE && $SOLR_CORE_FOUND -eq 0 ]]; then
        NAGIOS_MESSAGE="WARNING: Core $SOLR_CORE not found!"
        set_nagios_status $NAGIOS_WARNING
    fi

    for i in "${cores[@]}"
    do
        if [[ ! -z $SOLR_CORE && $SOLR_CORE != ${i} ]]; then
            continue
        fi
        core_ping=$(solr_request "${i}/admin/ping?wt=json")
        check_request "${core_ping}"
        core_ping=$(echo $core_ping | jq -r '.status')
        core_name=$(echo ${core_info} | jq -r ".status.\"${i}\".name")
        core_numDocs=$(echo ${core_info} | jq -r ".status.\"${i}\".index.numDocs")
        core_sizeInBytes=$(echo ${core_info} | jq -r ".status.\"${i}\".index.sizeInBytes")
        NAGIOS_DETAILS=( "${NAGIOS_DETAILS[@]}" "Core: ${core_name}, ping: ${core_ping}, numDocs: ${core_numDocs}, sizeInBytes: ${core_sizeInBytes}" )
        NAGIOS_PERF=( "${NAGIOS_PERF[@]}" "'core_${core_name}_numDocs'=${core_numDocs}" )
        NAGIOS_PERF=( "${NAGIOS_PERF[@]}" "'core_${core_name}_sizeInBytes'=${core_sizeInBytes}B" )
        if [ "$core_ping" != 'OK' ]; then
            NAGIOS_MESSAGE="WARNING: One or more cores are in warning state"
            set_nagios_status $NAGIOS_WARNING
        fi
        SOLR_CORE_FOUND=1
    done
}

check_jvm(){
    info_system=$(solr_request "admin/info/system?wt=json")
    check_request "${info_system}"
    jvm_used=$(echo $info_system | jq -r '.jvm.memory.raw.used')
    jvm_total=$(echo $info_system | jq -r '.jvm.memory.raw.total')
    jvm_used_percent=$(echo $info_system | jq -r '.jvm.memory.raw."used%"')
    jvm_used_percent=${jvm_used_percent%.*}

    if [[ ! -z $SOLR_CRITICAL && $jvm_used_percent -gt $SOLR_CRITICAL ]]; then
        NAGIOS_MESSAGE="CRITICAL: $jvm_used_percent% JVM memory usage"
        set_nagios_status $NAGIOS_WARNING
    elif [[ ! -z $SOLR_WARNING &&  $jvm_used_percent -gt $SOLR_WARNING ]]; then
        NAGIOS_MESSAGE="WARNING: $jvm_used_percent% JVM memory usage"
        set_nagios_status $NAGIOS_WARNING
    else
        NAGIOS_MESSAGE="OK: $jvm_used_percent% JVM memory usage"
    fi
    
    
    if [ ! -z $SOLR_CRITICAL ]; then
        critical_value=$(( SOLR_CRITICAL*jvm_total/100 ))
        critical_value=${critical_value%.*}
    fi
    if [ ! -z $SOLR_WARNING ]; then
        warning_value=$(( SOLR_WARNING*jvm_total/100 ))
        warning_value=${warning_value%.*}
    fi
    NAGIOS_PERF=( "${NAGIOS_PERF[@]}" "'jvm_memory'=${jvm_used}b;${warning_value};${critical_value};0;${jvm_total}" )
}

solr_request(){
    url=$1
    auth=
    extra=
    proto=http
    
    if [ $SOLR_SSL -eq 1 ]; then
        proto=https
        extra=' --insecure '
    fi
    
    if [ ! -z $SOLR_USER ]; then
        auth="$SOLR_USER:${SOLR_PASSWD/@/%40}@"
    fi

    curl_result=$(curl --silent ${extra} ${proto}://${auth}${SOLR_HOST}:${SOLR_PORT}/solr/${url})
    echo $curl_result
}

check_request(){
    request="$1"
    if [ -z "$request" ]; then
        set_nagios_status $NAGIOS_UNKNOWN
        NAGIOS_MESSAGE='UNKNOWN: No es posible conectar con el servidor'
        nagios_exit
    fi
    if ! jq -e . >/dev/null 2>&1 <<<"$request"; then
        set_nagios_status $NAGIOS_UNKNOWN
        NAGIOS_MESSAGE='UNKNOWN: No es posible recopilar la información del servidor'
        nagios_exit
    fi
}

function print_version(){
        echo "check_apache_solr.sh - version $VERSION"
        exit $NAGIOS_OK
}

function print_help(){
        echo "check_apache_solr.sh"
        echo ""

        echo "This plugin is not developped by the Nagios Plugin group."
        echo "Please do not e-mail them for support on this plugin."
        echo ""
        echo "For contact info, please read the plugin script file."
        echo ""
        echo "Usage: $0 -H <hostname> [-h] [-V]"
        echo "------------------------------------------------------------------------------------"
        echo "Usable Options:"
        echo ""
        echo "   -H <hostname>   ... Name or IP address of host to check"
        echo "   -p <port>       ... Name or IP address of host to check (default: 8983)"
        echo "   -u <username>   ... Basic authentication user"
        echo "   -P <password>   ... Basic authentication password"
        echo "   -C <core>       ... Solr core (default: *)"
        echo "   -S              ... Enable TLS/SSL (default: no)"
        echo "   -T              ... Test selection. Available options:"
        echo "                       - cores"
        echo "                       - jvm"
        echo "   -w              ... Warning threshold (default: 80)"
        echo "   -c              ... Critical threshold (default: 90)"
        echo "   -f              ... Perfparse compatible output (default: no)"
        echo "   -h              ... Show this help screen"
        echo "   -V              ... Show the current version of the plugin"
        echo ''
        echo 'Examples:'
        echo "    $0 -h 127.0.0.1 -u nagios -P P@\$\$w0rd"
        echo "    $0 -V"
        echo ""
        echo "------------------------------------------------------------------------------------"
        exit $NAGIOS_OK
}

# Show help if no parameters
if [ $# -eq 0 ]; then
    print_help
fi

# Read command line options
while getopts "H:p:u:P:C:w:c:T:fShV" OPTNAME;
do
    case $OPTNAME in
        "H")
            SOLR_HOST=$OPTARG;;
        "p")
            SOLR_PORT=$OPTARG;;
        "S")
            SOLR_SSL=1;;
        "u")
            SOLR_USER=$OPTARG;;
        "P")
            SOLR_PASSWD=$OPTARG;;
        "C")
            SOLR_CORE=$OPTARG;;
        "f")
            SOLR_PERF=1;;
        "w")
            SOLR_WARNING=$OPTARG;;
        "c")
            SOLR_CRITICAL=$OPTARG;;
        "T")
            SOLR_CHECK=$OPTARG;;
        "h")
            print_help;;
        "V")
            print_version;;
        *)
            print_help;;
    esac
done

if declare -f "check_${SOLR_CHECK}" > /dev/null; then
    SOLR_CHECK=check_${SOLR_CHECK}
    ${SOLR_CHECK}
    nagios_exit
else
    print_help
fi
