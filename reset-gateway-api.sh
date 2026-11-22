
#!/usr/bin/env bash
set -euo pipefail

echo "========================================"
echo " COMPLETE GATEWAY API / NGINX NGF RESET"
echo "========================================"
echo
echo "This removes ALL Gateway API resources"
echo "and NGINX Gateway Fabric installations."
echo "Other Gateway API users will be affected."
echo
echo "The genai namespace and vLLM are preserved."
echo

read -r -p "Type DELETE-GATEWAY-API to continue: " ANSWER
[[ "$ANSWER" == "DELETE-GATEWAY-API" ]] || exit 1

echo
echo "=== 1. Uninstall NGF Helm releases ==="

helm list -A --short | while read -r release; do
  [[ -z "$release" ]] && continue

  helm list -A -o json |
    python3 -c '
import json,sys
for x in json.load(sys.stdin):
    if x["name"] == sys.argv[1]:
        if ("nginx-gateway-fabric" in x.get("chart","")
            or x["name"] == "ngf"):
            print(x["name"], x["namespace"])
' "$release" |
  while read -r name namespace; do
    helm uninstall "$name" -n "$namespace" --wait
  done
done

echo "=== 2. Delete Gateway API resources ==="

# Remove custom resources before deleting their CRDs.
for resource in \
  httproutes \
  grpcroutes \
  tcproutes \
  tlsroutes \
  udproutes \
  referencegrants \
  backendtlspolicies \
  listenersets \
  gateways \
  gatewayclasses
do
  if kubectl api-resources --no-headers \
      | awk '{print $1}' | grep -qx "$resource"; then
    kubectl delete "$resource" --all -A \
      --ignore-not-found --wait=true || true
  fi
done

echo "=== 3. Delete NGINX-specific custom resources ==="

kubectl get crd -o name |
  grep '\.gateway\.nginx\.org$' |
  while read -r crd; do
    resource="${crd#*/}"
    kubectl delete "$resource" --all -A \
      --ignore-not-found --wait=true || true
  done

echo "=== 4. Delete generated NGINX data planes ==="

# Remove workloads owned by NGINX Gateway Fabric.
for kind in deployments services configmaps secrets \
            serviceaccounts roles rolebindings; do
  kubectl delete "$kind" -A \
    -l app.kubernetes.io/managed-by=ngf-nginx \
    --ignore-not-found --wait=true || true
done

echo "=== 5. Remove NGF namespaces ==="

kubectl delete namespace nginx-gateway \
  --ignore-not-found --wait=true

echo "=== 6. Remove Gateway API admission policies ==="

kubectl delete validatingadmissionpolicybinding \
  safe-upgrades.gateway.networking.k8s.io \
  --ignore-not-found

kubectl delete validatingadmissionpolicy \
  safe-upgrades.gateway.networking.k8s.io \
  --ignore-not-found

echo "=== 7. Delete Gateway API CRDs ==="

kubectl get crd -o name |
  grep '\.gateway\.networking\.k8s\.io$' |
  xargs -r kubectl delete --wait=true

echo "=== 8. Delete NGINX Gateway Fabric CRDs ==="

kubectl get crd -o name |
  grep '\.gateway\.nginx\.org$' |
  xargs -r kubectl delete --wait=true

echo "=== 9. Check for remaining NGF cluster resources ==="

for kind in clusterroles clusterrolebindings \
            validatingwebhookconfigurations \
            mutatingwebhookconfigurations; do
  kubectl get "$kind" -o name |
    grep -E '(^|/)(ngf-|nginx-gateway)' |
    while read -r resource; do
      echo "Removing $resource"
      kubectl delete "$resource"
    done || true
done

echo "=== 10. Verify cleanup ==="

echo "Remaining Gateway API CRDs:"
kubectl get crd -o name |
  grep -E 'gateway\.(nginx|networking)\.org|gateway\.networking\.k8s\.io' \
  || true

echo "Remaining Gateway API admission policies:"
kubectl get validatingadmissionpolicy,validatingadmissionpolicybinding \
  -o name 2>/dev/null |
  grep 'gateway.networking.k8s.io' || true

echo "Remaining NGF Helm releases:"
helm list -A | grep -E 'ngf|nginx-gateway' || true

echo
echo "=== Verify vLLM ==="
kubectl get deployment vllm -n genai
kubectl get service vllm -n genai

echo
echo "CLEANUP COMPLETE"

