#!/usr/bin/env bash

set -e

# This script might take about 30 minutes
# Please check the variables
RGLOCATION1=$1
RGLOCATION2=$2
RGNAMEHUB=$3
RGNAMESPOKES=$4
RGNAMECLUSTER=$5
AKS_CLUSTER_NAME1=$6
AKS_CLUSTER_NAME2=$7

__usage="
    [-c RGNAMECLUSTER]
    [-h RGNAMEHUB]
    [-k AKS_CLUSTER_NAME1]
    [-z AKS_CLUSTER_NAME2]
    [-l LOCATION1]
    [-e LOCATION2]
    [-p RGNAMESPOKES]
"

usage() {
    echo "usage: ${0##*/}"
    echo "${__usage/[[:space:]]/}"
    exit 1
}

while getopts "c:h:l:e:z:p:k:" opt; do
    case $opt in
    c)  RGNAMECLUSTER="${OPTARG}";;
    h)  RGNAMEHUB="${OPTARG}";;
    l)  RGLOCATION1="${OPTARG}";;
    e)  RGLOCATION2="${OPTARG}";;
    p)  RGNAMESPOKES="${OPTARG}";;
    k)  AKS_CLUSTER_NAME1="${OPTARG}";;
    z)  AKS_CLUSTER_NAME2="${OPTARG}";;
    *)  usage;;
    esac
done
shift $(( $OPTIND - 1 ))

if [ $OPTIND = 1 ]; then
    usage
    exit 0
fi

RGNAMEHUB1=${RGNAMEHUB}-${RGLOCATION1}
RGNAMEHUB2=${RGNAMEHUB}-${RGLOCATION2}
RGNAMESPOKES1=${RGNAMESPOKES}-${RGLOCATION1}
RGNAMESPOKES2=${RGNAMESPOKES}-${RGLOCATION2}
RGNAMECLUSTER1=${RGNAMECLUSTER}-${RGLOCATION1}
RGNAMECLUSTER2=${RGNAMECLUSTER}-${RGLOCATION2}

echo deleting $RGNAMECLUSTER1
az group delete -n $RGNAMECLUSTER1 --yes

echo deleting $RGNAMEHUB1
az group delete -n $RGNAMEHUB1 --yes

echo deleting $RGNAMESPOKES1
az group delete -n $RGNAMESPOKES1 --yes

echo deleting key vault soft delete
az keyvault purge --name kv-${AKS_CLUSTER_NAME1} --location ${RGLOCATION1}

echo deleting $RGNAMECLUSTER2
az group delete -n $RGNAMECLUSTER2 --yes

echo deleting $RGNAMEHUB2
az group delete -n $RGNAMEHUB2 --yes

echo deleting $RGNAMESPOKES2
az group delete -n $RGNAMESPOKES2 --yes

echo deleting key vault soft delete
az keyvault purge --name kv-${AKS_CLUSTER_NAME2} --location ${RGLOCATION2}