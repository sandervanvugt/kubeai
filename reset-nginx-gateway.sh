
#!/usr/bin/env bash
set -euo pipefail

echo "=== Remove vLLM Gateway API routing ==="

kubectl delete httproute vllm-route \
  -n genai --ignore-not-found

kubectl delete gateway vllm-gateway \
  -n genai --ignore-not-found

echo "=== Uninstall old or failed Helm release ==="

if helm status ngf -n nginx-gateway >/dev/null 2>&1; then
  helm uninstall ngf -n nginx-gateway --wait
fi

echo "=== Remove NGINX Gateway namespace ==="

kubectl delete namespace nginx-gateway \
  --ignore-not-found --wait=true

echo "=== Check NGINX-specific custom resources ==="

NGINX_CRDS=$(kubectl get crd -o name |
  grep '\.gateway\.nginx\.org$' || true)

if [[ -n "$NGINX_CRDS" ]]; then
  while IFS= read -r crd; do
    echo "Checking $crd"
    kubectl get "${crd#customresourcedefinition.apiextensions.k8s.io/}" \
      -A --ignore-not-found || true
  done <<< "$NGINX_CRDS"

  echo
  echo "WARNING: Deleting these CRDs also deletes"
  echo "all their associated custom resources."
  echo "Only continue if they belong to this lab."
  read -r -p "Delete NGINX-specific CRDs? [yes/NO] " answer

  if [[ "$answer" != "yes" ]]; then
    echo "Stopped without deleting CRDs."
    exit 1
  fi

  echo "$NGINX_CRDS" | xargs -r kubectl delete --wait=true
fi

echo "=== Verify old NGINX CRDs are gone ==="

kubectl get crd | grep 'gateway.nginx.org' || true

echo "=== Verify vLLM is still available ==="

kubectl get deployment vllm -n genai
kubectl get service vllm -n genai

echo "=== Cleanup complete ==="

