#!/bin/bash

# What is covered in this script
# Extauth - metrics/logs
# Gloo - metrics/logs
# gateway-proxy - metrics| loops over the pods in a given namespace.
#
# Creates a tar.gz in /tmp or any other directory

#BASE_DIR="/tmp"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'


usage() { echo -e "Usage: $0 [-d data directory] [-s since=0s,1h,24h default 1h] [-o output_zip_dir] -n namespace(Gateway-Proxy) \nExtauth/Gloo defaults to gloo-system [-g Gloo components namespace]"  1>&2; exit 1; }

while getopts ":d:o:s:n:g" p; do
    case "${p}" in
	s) STIME=${OPTARG}
	   ;;
	d)
	    BASE_DIR=${OPTARG}
	    ;;
        o)
            ZIP_DIR=${OPTARG}
            ;;
    	n) 
	    NAMESPACE=${OPTARG}
	    ;;
	g)
	    GLOO_NAMESPACE=${OPTARG}
	    ;;
        *)
            usage
            ;;
    esac
done

shift $((OPTIND-1))

if [ -z "${NAMESPACE}" ]; then
	echo -e "\n${RED}No gateway-proxy namespace provided${NC}\n"
	usage
fi

if [ -z "${BASE_DIR}" ]; then
	BASE_DIR="/tmp"
	echo -e "${YELLOW}Using ${BASE_DIR} as the default base directory${NC}"

fi

if [ -z "${ZIP_DIR}" ]; then
	ZIP_DIR="/tmp"
	echo -e "${YELLOW}Using ${ZIP_DIR} as the default for Zipping files${NC}"

fi


if [ -z "${STIME}" ]; then
	STIME="1h"
	echo -e "${YELLOW}Using ${STIME} as the default for log time${NC}"

fi

if [ -z "${GLOO_NAMESPACE}" ]; then
	GLOO_NAMESPACE="gloo-system"
	echo -e "${YELLOW}Using ${GLOO_NAMESPACE} for Gloo Components${NC}"

fi


file_random=$(date +%Y%m%d_%s%H)


DATA_DIR="${BASE_DIR}/gloo-${file_random}"
DEPLOYMENT_EXTAUTH="extauth"
DEPLOYMENT_GLOO="gloo"


EXTAUTH_METRICS_FILE="${DATA_DIR}/extauth_metrics_${file_random}.txt"
GLOO_METRICS_FILE="${DATA_DIR}/gloo_metrics_${file_random}.txt"
GLOOCTL_CHECK_FILE="${DATA_DIR}/glooctl_check_${file_random}.txt"


if ! command -v glooctl &> /dev/null; then
	echo -e "${RED}glooctl isn't installed${NC}"
	exit 1
fi

check_kubectl=$(command -v kubectl)
check_oc=$(command -v oc)
check_glooctl=$(command -v glooctl)

if command -v kubectl; then
	kubectl=$check_kubectl
	killall kubectl
elif command -v oc; then
	kubectl=$check_oc
	killall oc
else 
	echo -e "${RED}Kubectl or oc isn't found exiting...${NC}"
	exit 2
fi
echo -e "${YELLOW}using ${kubectl}${NC}"

# Since the pods are scaled, might be better to iterate over pod_names => curl it => kill-it => repeat.

# Extauth
# kubectl get pods -l "gloo=extauth" -n gloo-system  -o jsonpath=”{.items[*].metadata.name}”

# Gloo
# kubectl get pods -l "gloo=gateway-proxy" -n gloo-system  -o jsonpath=”{.items[*].metadata.name}”

# Searching by label gets all the pods with prefix.

echo "Gathering Data for $($kubectl config current-context)"

# Store it in a data_dir, zip it at the end.

mkdir -p "$DATA_DIR"
cd "$DATA_DIR" || exit

if [ "$DATA_DIR" != "$PWD" ] ;then
	echo -e "${RED}This isn't the data directory${NC}"
	exit 1
fi
sleep 1

echo -e "${YELLOW}Storing data in $DATA_DIR${NC}"


# loop_pods gloo=extauth
# Doesn't support gateway_proxy

loop_pods () {
EX_PODS=$($kubectl get pods -l "$1" -n "$GLOO_NAMESPACE" -o jsonpath={.items[*].metadata.name})
ex_podnames=($EX_PODS)
for i in "${ex_podnames[@]}"; do
	echo -e "${YELLOW}Running kubectl port-forward -n ${GLOO_NAMESPACE} pods/${i} ${NC}"
	kubectl port-forward -n "${GLOO_NAMESPACE}" pods/"${i}" 9091:9091 &> /dev/null  &
	ex_PID=$!
	sleep 2
	curl -s localhost:9091/metrics -o "${DATA_DIR}/${i}_metrics_${file_random}.txt" &> /dev/null
	sleep 1
	kill $ex_PID
	sleep 1
	unset ex_PID

done

}

# extauth

echo -e "\n${YELLOW}Curling extauth metrics${NC}"
loop_pods gloo=extauth

echo -e "${YELLOW}Get Extauth Logs since ${STIME} ${NC}"
$kubectl logs --since=${STIME} -l gloo=extauth -n ${GLOO_NAMESPACE}  --prefix > "${DATA_DIR}/extauth_logs_${file_random}.txt"
#$kubectl port-forward deployment/${DEPLOYMENT_EXTAUTH} -n ${GLOO_NAMESPACE} 9091:9091 &> /dev/null &
#extauth_PID=$!

sleep 1

# gloo pod
echo -e "\n${YELLOW}Curling gloo metrics${NC}"

loop_pods gloo=gloo
#$kubectl port-forward deployment/${DEPLOYMENT_GLOO} -n ${GLOO_NAMESPACE} 9091:9091 &> /dev/null &
#gloo_PID=$!

echo -e "${YELLOW}Get Gloo Logs since ${STIME} ${NC}"
$kubectl logs --since=${STIME} -l gloo=gloo -n ${GLOO_NAMESPACE}  --prefix > "${DATA_DIR}/gloo_logs_${file_random}.txt"
#sleep 1

#curl -s localhost:9091/metrics -o "$GLOO_METRICS_FILE"

sleep 1
#kill $gloo_PID

echo -e "${YELLOW}\nGetting metrics from gateway-proxy pods${NC}"

GW_PODS=$(kubectl get pods -l "gloo=gateway-proxy" -n "$NAMESPACE" -o jsonpath={.items[*].metadata.name})

#echo "$GW_PODS"

echo -e  "${YELLOW}Curl to gateway-proxies${NC}"
pod_names=($GW_PODS)
#for i in "${pod_names[@]}"; do
for i in "${pod_names[@]}"; do
	echo -e "${YELLOW}Running kubectl port-forward -n ${NAMESPACE} pods/${i} ${NC}"
	kubectl port-forward -n "${NAMESPACE}" pods/"${i}" 19000:19000 &> /dev/null  &
	gw_PID=$!
	sleep 2
	curl -s localhost:19000/stats -o "${DATA_DIR}/${i}_metrics_${file_random}.txt" &> /dev/null
	curl -s -X POST "localhost:19000/config_dump?include_eds" > "${DATA_DIR}/${i}_config_dump_${file_random}.txt"
	# Don't log this it's on a PV and can be in GB's
	# echo -e "${YELLOW} Get ${i} Logs ${NC}"
	kubectl logs pods/"${i}" -n "${NAMESPACE}"  --prefix >  "${DATA_DIR}/${i}_access_logs_${file_random}.txt"
	sleep 1
	kill $gw_PID
	unset gw_PID

done

echo -e "\n${YELLOW}Gathering Extauth, Gloo, Gateway-proxy Pod names and IP and upstreams"
kubectl get pods -l "gloo=gateway-proxy" -n "$NAMESPACE" -o jsonpath='{range .items[*]}{@.metadata.name}{" "}{@.status.podIPs}{"\n"}{end}' >> "${DATA_DIR}/pod_info_${file_random}.txt"
kubectl get pods -l "gloo=extauth" -n "$GLOO_NAMESPACE" -o jsonpath='{range .items[*]}{@.metadata.name}{" "}{@.status.podIPs}{"\n"}{end}' >> "${DATA_DIR}/pod_info_${file_random}.txt"
kubectl get pods -l "gloo=gloo" -n "$GLOO_NAMESPACE" -o jsonpath='{range .items[*]}{@.metadata.name}{" "}{@.status.podIPs}{"\n"}{end}' >> "${DATA_DIR}/pod_info_${file_random}.txt"

kubectl get upstreams -A -o yaml>> "${DATA_DIR}/upstreams_${file_random}.txt"

echo -e "\n${YELLOW}Running Glooctl check${NC}"
glooctl check &> "$GLOOCTL_CHECK_FILE" 

echo -e "\n${YELLOW}Zipping tar -czvf ${ZIP_DIR}/gloo_${file_random}.tar.gz $DATA_DIR ${NC}"
tar -czvf "${ZIP_DIR}/gloo_${file_random}.tar.gz" "$DATA_DIR" &> /dev/null

echo -e "${GREEN} Data Directory ${DATA_DIR} ${NC}"
echo -e "${GREEN} ZIP ${ZIP_DIR}/gloo_${file_random}.tar.gz ${NC}"
echo -e "${GREEN}Complete...${NC}"
