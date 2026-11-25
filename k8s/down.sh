#!/usr/bin/env bash
# Delete the local kind cluster (and everything in it, databases included).
set -euo pipefail
kind delete cluster --name zync
