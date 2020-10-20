#!/bin/sh
# Requirements = curl, jq
# Must set ${DIGITALOCEAN_TOKEN} and ${FLOATING_IP}

K8S_CURL_ARGS="--cacert /run/secrets/kubernetes.io/serviceaccount/ca.crt"
KUBE_API_ENDPOINT="${KUBE_API_ENDPOINT:-"https://kubernetes.default.svc:443"}"
SLEEP_TIME="${SLEEP_TIME:-"30"}"

LABEL_SELECTOR=""
if [[ ! -z "${NODE_SELECTOR}" ]]; then
  LABEL_SELECTOR="?labelSelector=${NODE_SELECTOR}"
fi

if [[ -z "${DIGITALOCEAN_TOKEN}" ]]; then
  echo "FATAL - Variable DIGITALOCEAN_TOKEN must be provided"
  exit 1
fi

if [[ -z "${FLOATING_IP}" ]]; then
  echo "FATAL - Variable FLOATING_IP must be provided"
  exit 1
fi

# Pipe in v1/Node JSON and get back the droplet ID
function get_node_droplet_id(){
  jq -cr '.metadata.annotations."csi.volume.kubernetes.io/nodeid" | fromjson | ."dobs.csi.digitalocean.com"'
}

# Returns a JSON list of nodes
function get_node_list(){
  K8S_TOKEN="$(cat /run/secrets/kubernetes.io/serviceaccount/token)"
  curl -s ${K8S_CURL_ARGS} \
    --header "Authorization: Bearer ${K8S_TOKEN}" \
    "${KUBE_API_ENDPOINT}/api/v1/nodes${LABEL_SELECTOR}" \
  | jq -cr
}

# Returns the droplet ID where the IP is currently assigned or null
function get_current_droplet_id(){
  curl -sX GET -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${DIGITALOCEAN_TOKEN}" \
    "https://api.digitalocean.com/v2/floating_ips/${FLOATING_IP}" \
  | jq -cr '.floating_ip.droplet // {id:null} | .id'
}

# Assigns a floating ip to a droplet
# Usage: assign_floating_ip x.x.x.x <dropletId>
function assign_floating_ip(){
  IP="${1}"
  DROPLET_ID="${2}"
  curl -O /dev/null -sX POST -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${DIGITALOCEAN_TOKEN}" \
    -d '{"type":"assign","droplet_id":'${DROPLET_ID}'}' \
    "https://api.digitalocean.com/v2/floating_ips/${IP}/actions"
}

# Gets a droplet name from its id
# Usage: get_droplet_name <dropletId>
function get_droplet_name(){
  DROPLET_ID="${1}"
  get_node_list | jq -r '.items[] | select(.metadata.annotations."csi.volume.kubernetes.io/nodeid" | fromjson | ."dobs.csi.digitalocean.com" == "'${DROPLET_ID}'") | .metadata.name'
}

# Sets a label on a node
# Usage: set_node_label <dropletId> <labelKey> <labelValue>
function set_node_label(){
  DROPLET_ID="${1}"
  KEY="${2}"
  VALUE="${3}"
  DROPLET_NAME=$(get_droplet_name ${DROPLET_ID})
  K8S_TOKEN="$(cat /run/secrets/kubernetes.io/serviceaccount/token)"
  curl -O /dev/null -sX PATCH ${K8S_CURL_ARGS} -H "Content-Type: application/json-patch+json" \
    --header "Authorization: Bearer ${K8S_TOKEN}" \
    "${KUBE_API_ENDPOINT}/api/v1/nodes/${DROPLET_NAME}" \
    --data '[{"op": "add", "path": "/metadata/labels/'${KEY}'", "value": "'${VALUE}'"}]'
}

# Deletes a label from a node
# Usage: delete_node_label <dropletId> <labelKey>
function remove_node_label() {
  DROPLET_ID="${1}"
  KEY="${2}"
  DROPLET_NAME=$(get_droplet_name ${DROPLET_ID})
  K8S_TOKEN="$(cat /run/secrets/kubernetes.io/serviceaccount/token)"
  curl -O /dev/null -sX PATCH ${K8S_CURL_ARGS} -H "Content-Type: application/json-patch+json" \
    --header "Authorization: Bearer ${K8S_TOKEN}" \
    "${KUBE_API_ENDPOINT}/api/v1/nodes/${DROPLET_NAME}" \
    --data '[{"op": "remove", "path": "/metadata/labels/'${KEY}'"}]'
}

function run_main(){
  ASSIGNED_TO=$(get_current_droplet_id)
  DROPLET=$(get_node_list | jq '.items[0]' | get_node_droplet_id)
  if [[ "${ASSIGNED_TO}" == "${DROPLET}" ]]; then
    echo "Already assigned - Doing nothing" >> /dev/null
  else
    if [[ "${ASSIGNED_TO}" == "null" ]]; then
      echo "Attaching IP to droplet ${DROPLET}"
    else
      echo "Moving IP from droplet ${ASSIGNED_TO} to droplet ${DROPLET}"
      remove_node_label $DROPLET "floating_ip"
    fi
    assign_floating_ip ${FLOATING_IP} ${DROPLET}
    set_node_label $DROPLET "floating_ip" "${FLOATING_IP}"
  fi
}

while true; do
  run_main
  sleep ${SLEEP_TIME}
done
