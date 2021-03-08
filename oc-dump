#!/bin/bash

# This script produces a dump of the specified project. It includes all namespaced resources information and pod logs.
#
# https://access.redhat.com/solutions/3340581
#
# Usage:
#
# $ curl -LO https://raw.githubusercontent.com/nekop/shiftbox/master/oc-dump
# $ chmod +x ./oc-dump
# $ ./oc-dump PROJECT

PROJECT=$1
OC="oc -n $PROJECT"
DEST=$PROJECT-$(date +%Y%m%d%H%M%S).txt.gz

if [ -z $PROJECT ]; then
  echo "Usage: $0 PROJECT"
  exit 1
fi

oc get project $PROJECT >& /dev/null
if [ $? -ne 0 ]; then
  echo "Project $PROJECT does not exist"
  exit 1
fi

if [ ! "$($OC auth can-i get pod/logs)" == "yes" ]; then
  echo "User $($OC whoami) does not have permissions to read the pod logs in $PROJECT"
  exit 1
fi

echo "Generating dump for project $PROJECT, it may take about 20 sec - 2 min"

(
  set -x
  date
  $OC whoami
  $OC project $PROJECT
  $OC version
  $OC status
  $OC get project $PROJECT -o yaml
  # Combine api-resources output into single parameter to minimize the number of API requests. Do not DoS attack the API by for each loop.
  # You might want to search "get secret" but it doens't work because of the combined single parameter format. Instead, search the output format like: zegrep -n '^secret|^  kind: Secret' output.txt.gz
  API_RESOURCES=$($OC api-resources -o name --namespaced --verbs=list | awk '{printf "%s%s",sep,$0; sep=","}')
  $OC get --ignore-not-found $API_RESOURCES -o wide
  $OC get --ignore-not-found $API_RESOURCES -o yaml
  # oc get events with absolute timestamp, human readable troubleshoorting friendly format
  $OC get event -o custom-columns="LAST SEEN:{lastTimestamp},FIRST SEEN:{firstTimestamp},COUNT:{count},NAME:{metadata.name},KIND:{involvedObject.kind},SUBOBJECT:{involvedObject.fieldPath},TYPE:{type},REASON:{reason},SOURCE:{source.component},MESSAGE:{message}"
  PODS=$($OC get pod -o name)
  for pod in $PODS; do
    CONTAINERS=$($OC get $pod --template='{{range .spec.containers}}{{.name}}
{{end}}')
    for c in $CONTAINERS; do
      $OC logs $pod --container=$c --timestamps
      $OC logs -p $pod --container=$c --timestamps
    done
  done
  # if it has cluster-reader or cluster-admin, get additional info
  if [ "$($OC auth can-i get nodes)" == "yes" ]; then
    $OC get node -o wide
    $OC get node -o yaml
    $OC describe node
    $OC get hostsubnet
    $OC get scc -o yaml
    $OC get clusterrolebinding -o yaml
    $OC get storageclass -o wide
    $OC get storageclass -o yaml
    $OC get pv -o wide
    $OC get pv -o yaml
    $OC get csr
    $OC get pods -o wide --all-namespaces
  fi
  date
) 2>&1 | gzip > $DEST
echo "Generated $DEST"
# end
