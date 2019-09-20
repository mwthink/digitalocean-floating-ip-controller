# digitalocean-floatingip-controller
Keeps floating IPs assigned to your Kubernetes cluster

## Overview
This project is intended to be run as a Kubernetes pod inside a
DOK ([DigitalOcean Kubernetes](https://www.digitalocean.com/products/kubernetes/)) cluster.

The controller will assign a floating IP (via the DigitalOcean API) to a
cluster node. The lifecycle of the application is:
1. Get list of nodes
2. Select a node to assign
  - Currently the first returned node is selected
3. Check if the IP is already assigned to this node
  - If so, do nothing
  - If not, assign it
4. Sleep for a time, then repeat

## Configuration
You **must** provide the following as *environment variables*:
- `DIGITALOCEAN_TOKEN`
  - DigitalOcean API token
- `FLOATING_IP`
  - Floating IP address that this controller manages

You _can_ provide the following as *environment variables*:
- `NODE_SELECTOR`
  - Value for `labelSelector` on the node query

## Deploy
You can customize the `deploy.yaml` file then `kubectl apply` it to
install to a cluster. You can also use `kustomize` in the subdirectory.
