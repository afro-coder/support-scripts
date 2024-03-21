#!/bin/bash

# Scope 
# soloio crds
# Authconfigs, virtualservices,

#TODO
# switch to bash opts for OC/Kubectl
# Gateway-proxy required data
# Extauth required data
#


DATA_DIR="/tmp/gloo-$(date +%Y%m%d)"
GLOO_NAMESPACE="gloo-system"
DEPLOYMENT_EXTAUTH="extauth"
EXTAUTH_METRICS_FILE="${DATA_DIR}/extauth_metrics-$(date +%Y%m%d).txt"
GlOO_METRICS_FILE="${DATA_DIR}/gloo_metrics-$(date +%Y%m%d).txt"
GlOOCTL_CHECK_FILE="${DATA_DIR}/glooctl_check-$(date +%Y%m%d).txt"

if ! command -v glooctl &> /dev/null; then
	echo "glooctl isn't installed"
	exit 1
fi

check_kubectl=$(command -v kubectl)
check_oc=$(command -v oc)
check_glooctl=$(command -v glooctl)

if command -v kubectl; then
	kubectl=$check_kubectl
elif command -v oc; then
	kubectl=$check_oc
else 
	echo "Kubectl or oc isn't found exiting..."
	exit 2
fi
echo "using ${kubectl}"

# Port forward ext-auth to 9091
#killall kubectl

# Since the pods are scaled, might be better to iterate over pod_names => curl it => kill-it => repeat.

# Extauth
# kubectl get pods -l "gloo=extauth" -n gloo-system  -o jsonpath=”{.items[*].metadata.name}”

# Gloo
# kubectl get pods -l "gloo=gateway-proxy" -n gloo-system  -o jsonpath=”{.items[*].metadata.name}”

$kubectl port-forward deployment/extauth -n ${GLOO_NAMESPACE} 9091:9091 &> /dev/null &
extauth_PID=$!

echo "Gathering Data for $(kubectl config current-context)"

# Store it in a data_dir, zip it at the end.

mkdir -p "$DATA_DIR"
cd "$DATA_DIR" || exit

if [ "$DATA_DIR" != "$PWD" ] ;then
	echo "This isn't the data directory"
	exit 1
fi
sleep 1

echo "Storing data in $DATA_DIR"
echo "Curling extauth metrics"
curl -v localhost:9091/metrics | tee "$EXTAUTH_METRICS_FILE" 

# Clean up port-forward
kill $extauth_PID

echo -e "\nRunning Glooctl check"
glooctl check > "$GLOOCTL_CHECK_FILE" 1>&2
