
#!/usr/bin/env bash
# Reset the vLLM Prometheus-based HPA lab.
# Keeps Prometheus, vLLM, and their configurations intact.

set -euo pipefail

NAMESPACE="genai"
MONITORING_NAMESPACE="monitoring"

echo "=== Cleaning up vLLM HPA lab ==="

# 1. Remove HPA
echo "[1/4] Removing HPA..."
kubectl delete hpa vllm-hpa \
  -n "$NAMESPACE" \
  --ignore-not-found

# 2. Remove Prometheus Adapter
echo "[2/4] Removing Prometheus Adapter..."
if helm status prometheus-adapter \
    -n "$MONITORING_NAMESPACE" >/dev/null 2>&1; then

  helm uninstall prometheus-adapter \
    -n "$MONITORING_NAMESPACE"
else
  echo "Prometheus Adapter is not installed."
fi

# 3. Reset vLLM to one replica
echo "[3/4] Resetting vLLM to one replica..."
kubectl scale deployment vllm \
  -n "$NAMESPACE" \
  --replicas=1

# 4. Verify remaining components
echo "[4/4] Checking remaining components..."

echo
echo "Prometheus:"
helm status prometheus \
  -n "$MONITORING_NAMESPACE" | grep -E 'NAME:|STATUS:'

echo
echo "vLLM:"
kubectl get deployment vllm -n "$NAMESPACE"
kubectl get pods -n "$NAMESPACE" -l app=vllm

echo
echo "=== Cleanup complete ==="
echo "Prometheus remains installed."
echo "vLLM remains deployed with one replica."
echo "HPA and Prometheus Adapter have been removed."
echo
echo "Resume the lab at Step 2:"
echo "Verify that Prometheus collects vLLM metrics."

