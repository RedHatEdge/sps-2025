#!/bin/bash


TARGET_FOLDER="charts"
IMAGE_LIST_ONCITE="./oncite-container-refs.txt"

for CHART in "$TARGET_FOLDER"/*.tgz; do
  FILENAME=${CHART##*/}
  CHARTNAME=${FILENAME%%-[0-9]*}
  helm template -f $TARGET_FOLDER/$CHARTNAME-mirror-values.yaml $CHART | grep -Eo '([[:alnum:].-]+(:[0-9]+)?/)?([[:alnum:]_.-]+/)+[[:alnum:]_.-]+:[[:alnum:]_.-]+' | grep -v '://' | sed -E 's|^([^/]+/[^/]+:[^:]+)$|docker.io/\1|' | sort -u  >> ${IMAGE_LIST_ONCITE}
  echo "Processed '$CHART' successfully"
done
