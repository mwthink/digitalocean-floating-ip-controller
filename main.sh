#!/bin/sh
# Requirements = curl, jq
# Must set ${DIGITALOCEAN_TOKEN} and ${FLOATING_IP}

K8S_CURL_ARGS="--cacert /run/secrets/kubernetes.io/serviceaccount/ca.crt"
KUBE_API_ENDPOINT="${KUBE_API_ENDPOINT:-"https://kubernetes.default.svc:443"}"
SLEEP_TIME="${SLEEP_TIME:-"30"}"
NODE_SELECTOR="${NODE_SELECTOR}"

NODE_SELECTOR="?labelSelector="
if [[ ! -z "${NODE_SELECTOR}" ]]; then
  NODE_SELECTOR="labelSelector=${NODE_SELECTOR}"
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
    "${KUBE_API_ENDPOINT}/api/v1/nodes?${NODE_SELECTOR}" \
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
    fi
    assign_floating_ip ${FLOATING_IP} ${DROPLET}
  fi
}

while true; do
  run_main
  sleep ${SLEEP_TIME}
done
