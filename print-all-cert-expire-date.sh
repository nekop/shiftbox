#!/bin/bash
# shellcheck disable=SC2029
# shellcheck disable=SC2206

##
## Oiginal code: https://github.com/nekop/shiftbox/blob/master/v3-print-all-certs-expire-date
## Script to print all TLS Cert Expire Date for OpenShift v3
##

function usage(){
    echo "Script Version 1.2
    usage: print-all-cert-expire-date.sh [-e] [-h]

    Optional arguments:
    pattern                         host pattern
    -l,                             To check Certificates in /etc/origin/node on localhost
    -s,                             To check Certificates in /etc/origin/node OVER SSH (SSH password-less and SUDO Without Pass REQUERED)
    -e,                             To set the missing DAYS to check before Certificates EXPIRES (Default 60 Days)
    -h, --help                      Show this help message and exit
    ––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
    "
}

# Set Shell TEXT COLOR
RED='\033[0;31m' # RED
NC='\033[0m' # No Color

# Default Missing Days before CERTS expire
DAYS_NUMBER=60

# Set Optional arguments if present
if [ "$1" != "" ]; then
    while [ "$1" != "" ]; do
      case $1 in
          -l )                    CHECK_LOCAL_NODE=true
                                  ;;
          -s )                    CHECK_OVER_SSH=true
                                  ;;
          -e )                    [[ $2 =~ ^[0-9]+$ ]] && shift && DAYS_NUMBER=$1
                                  ;;
          -h | --help )           usage
                                  exit
                                  ;;
          * )                     usage
                                  echo -e "Error for args: $1\n"
                                  exit 1
      esac
      shift
    done
fi


function show_cert() {
  ## - Do not use `openssl x509 -in` command which can only handle first cert in a given input
  CERT_VALIDITY=$(openssl crl2pkcs7 -nocrl -certfile /dev/stdin | openssl pkcs7 -print_certs -text \
    | openssl x509 -dates -noout -checkend $((60*60*24*DAYS_NUMBER)))
  if [ $? == 0 ]; then
    echo "${CERT_VALIDITY}"
  else
    echo -ne "${RED}"
    echo "${CERT_VALIDITY}"
    echo "--------------------------- EXPIRED within ${DAYS_NUMBER} DAYS ---------------------------"
    echo -ne "${NC}"
  fi
}



## Process all service serving cert secrets
echo -e "\n\n------------------------- Process all SERVICE with TLS cert on Secret -------------------------"
oc get service --no-headers --all-namespaces -o custom-columns='NAMESPACE:{metadata.namespace},NAME:{metadata.name},SERVING CERT:{metadata.annotations.service\.alpha\.openshift\.io/serving-cert-secret-name}' |
while IFS= read -r line; do
   items=( $line )
   NAMESPACE=${items[0]}
   SERVICE=${items[1]}
   SECRET=${items[2]}
   if [ "$SECRET" == "<none>" ]; then
     continue
   fi
   echo "- secret/$SECRET -n $NAMESPACE - SERVICE: $SERVICE"
   oc get secret/"$SECRET" -n "$NAMESPACE" --template='{{index .data "tls.crt"}}'  | base64 -d | show_cert
done


## Process other custom TLS secrets, router, docker-registry, logging and metrics components
echo -e "\n\n------------------------- Process all Secrets from list with TLS cert -------------------------"
cat <<EOF |
default router-certs tls.crt
default registry-certificates registry.crt
kube-service-catalog apiserver-ssl tls.crt
openshift-metrics-server metrics-server-certs ca.crt
openshift-metrics-server metrics-server-certs tls.crt
openshift-logging logging-elasticsearch admin-ca
openshift-logging logging-elasticsearch admin-cert
openshift-logging logging-curator ca
openshift-logging logging-curator cert
openshift-logging logging-fluentd ca
openshift-logging logging-fluentd cert
openshift-logging logging-fluentd ops-ca
openshift-logging logging-fluentd ops-cert
openshift-logging logging-kibana ca
openshift-logging logging-kibana cert
openshift-logging logging-kibana-proxy server-cert
openshift-infra hawkular-metrics-certs ca.crt
openshift-infra hawkular-metrics-certs tls.crt
openshift-infra hawkular-metrics-certs tls.truststore.crt
openshift-infra hawkular-cassandra-certs tls.crt
openshift-infra hawkular-cassandra-certs tls.client.truststore.crt
openshift-infra hawkular-cassandra-certs tls.peer.truststore.crt
openshift-infra heapster-certs tls.crt
EOF
while IFS= read -r line; do
  items=( $line )
  NAMESPACE=${items[0]}
  SECRET=${items[1]}
  FIELD=${items[2]}
  echo -e "\n--- secret/$SECRET -n $NAMESPACE, field: $FIELD"
  oc get secret/$SECRET -n "$NAMESPACE" --template="{{index .data \"$FIELD\"}}"  | base64 -d | show_cert
done

## Process all cert files under /etc/origin/{master,node} directories on each node
### This requires password-less SSH access to all nodes
if [ "$CHECK_OVER_SSH" == "true" ]; then
  echo -e "\n------------------------- Process all cert files under /etc/origin/{master,node} directories -------------------------"
  for node in $(oc get nodes --no-headers -o 'custom-columns=NAME:.metadata.name'); do
    echo "------------- NODE: $node -------------"

    for cert in $(ssh "$node" "sudo find /etc/origin/{master,node} -xtype f \( -name '*crt' -o -name '*pem' \) 2> /dev/null" | grep -Ev "kubelet-[c,s].*-[0-9]"); do
      echo "#### CERT: $cert ####"
      ssh "$node" "sudo cat ${cert}" | show_cert
    done

    for kubeconfig in $(ssh "$node" "sudo find /etc/origin/{master,node} -type f -name '*kubeconfig' 2> /dev/null" | grep -Ev "kubelet-[c,s].*-[0-9]"); do
      echo "#### KUBECONFIG: $kubeconfig ####"
      ssh "$node" "sudo cat ${kubeconfig}" | awk '/cert/ {print $2}' "$f" | base64 -d 2> /dev/null | show_cert
    done
  done
fi


## Process all cert files under /etc/origin/{master,node} directories on each node
if [ "$CHECK_LOCAL_NODE" == "true" ]; then
  echo -e "\n------------------------- Process all cert files under /etc/origin/{master,node} directories -------------------------"
  CERT_FILES=$(sudo find /etc/origin/{master,node} -xtype f \( -name '*crt' -o -name '*pem' \) 2> /dev/null | grep -Ev "kubelet-[c,s].*-[0-9]")
  for cert in $CERT_FILES; do
    echo "- $cert"
    show_cert < "$cert"
  done

  KUBECONFIG_FILES=$(find /etc/origin/{master,node} -type f -name '*kubeconfig' 2> /dev/null | grep -Ev "kubelet-[c,s].*-[0-9]")
  for f in $KUBECONFIG_FILES; do
    echo "- $f"
    awk '/cert/ {print $2}' "$f" | base64 -d 2> /dev/null | show_cert
  done
fi
