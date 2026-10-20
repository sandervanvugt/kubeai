
#!/usr/bin/env bash

# vLLM Continuous Load Test for Kubernetes
#
# Automatically discovers the vllm Service in namespace genai.
#
# Usage:
#   ./test-vllm-concurrent.sh [concurrency] [duration] [tokens]
#
# Examples:
#   ./test-vllm-concurrent.sh 2 60 200
#   ./test-vllm-concurrent.sh 10 180 400
#   ./test-vllm-concurrent.sh 20 180 600

set -u

# --------------------------------------------------
# Configuration
# --------------------------------------------------

NAMESPACE="genai"
SERVICE="vllm"
MODEL="Qwen/Qwen2.5-1.5B-Instruct"

CONCURRENCY="${1:-10}"
DURATION="${2:-180}"
MAX_TOKENS="${3:-400}"

# --------------------------------------------------
# Validate arguments and dependencies
# --------------------------------------------------

for cmd in kubectl curl awk; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: Required command '$cmd' not found."
    exit 1
  fi
done

for value in "$CONCURRENCY" "$DURATION" "$MAX_TOKENS"; do
  if ! [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: Arguments must be positive integers."
    exit 1
  fi
done

# --------------------------------------------------
# Discover the vLLM Service IP automatically
# --------------------------------------------------

echo "Discovering vLLM Service in namespace $NAMESPACE..."

if ! kubectl get service "$SERVICE" \
  -n "$NAMESPACE" >/dev/null 2>&1; then

  echo
  echo "ERROR: Required Kubernetes Service not found."
  echo
  echo "This test requires a Service named '$SERVICE'"
  echo "in the '$NAMESPACE' namespace."
  echo
  echo "Verify using:"
  echo "  kubectl get svc -n $NAMESPACE"
  echo
  echo "Deploy the vLLM Service before running this test."
  exit 1
fi

VLLM_SVC_IP=$(kubectl get service "$SERVICE" \
  -n "$NAMESPACE" \
  -o jsonpath='{.spec.clusterIP}')

if [[ -z "$VLLM_SVC_IP" || "$VLLM_SVC_IP" == "None" ]]; then
  echo "ERROR: Service '$SERVICE' has no valid ClusterIP."
  exit 1
fi

VLLM_URL="http://${VLLM_SVC_IP}:8000"

echo "Found vLLM Service IP: $VLLM_SVC_IP"

# --------------------------------------------------
# Initialize test
# --------------------------------------------------

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

END_TIME=$(( $(date +%s) + DURATION ))

PROMPTS=(
  "Explain Kubernetes networking in detail."
  "Explain how Kubernetes schedules Pods onto nodes."
  "Describe Kubernetes storage architecture."
  "Explain Kubernetes GPU scheduling and resource management."
  "Describe how a large language model performs inference."
  "Explain the differences between Ollama and vLLM."
  "Describe how Kubernetes Services and DNS work."
  "Explain how Prometheus monitors Kubernetes workloads."
)

echo
echo "========================================"
echo "vLLM Concurrent Load Test"
echo "========================================"
echo "Namespace:    $NAMESPACE"
echo "Service:      $SERVICE"
echo "Service IP:   $VLLM_SVC_IP"
echo "Endpoint:     $VLLM_URL"
echo "Model:        $MODEL"
echo "Concurrency:  $CONCURRENCY"
echo "Duration:     $DURATION seconds"
echo "Max tokens:   $MAX_TOKENS"
echo "========================================"

# --------------------------------------------------
# Check vLLM API availability
# --------------------------------------------------

echo
echo "Checking vLLM API availability..."

if ! curl -fsS --max-time 10 \
  "$VLLM_URL/health" >/dev/null; then

  echo
  echo "ERROR: vLLM API is not responding."
  echo
  echo "Check the following:"
  echo "  kubectl get pods -n $NAMESPACE"
  echo "  kubectl logs -n $NAMESPACE deployment/vllm"
  echo
  echo "The machine running this script must be able"
  echo "to reach Kubernetes ClusterIP Services."
  exit 1
fi

echo "vLLM API is responding."

# --------------------------------------------------
# Worker function
# --------------------------------------------------

worker() {
  local id=$1
  local prompt
  local payload
  local result
  local status
  local elapsed

  while (( $(date +%s) < END_TIME )); do

    prompt="${PROMPTS[$((RANDOM % ${#PROMPTS[@]}))]}"

    payload=$(printf \
      '{"model":"%s","messages":[{"role":"user","content":"%s Write a comprehensive explanation with practical examples and implementation details."}],"max_tokens":%d,"temperature":0.8,"ignore_eos":true}' \
      "$MODEL" "$prompt" "$MAX_TOKENS")

    result=$(curl -sS \
      --connect-timeout 5 \
      --max-time 180 \
      -o /dev/null \
      -w '%{http_code} %{time_total}' \
      -H "Content-Type: application/json" \
      -d "$payload" \
      "$VLLM_URL/v1/chat/completions" 2>/dev/null)

    read -r status elapsed <<< "$result"

    printf '%s %s\n' "${status:-000}" "${elapsed:-0}" \
      >> "$WORKDIR/requests.log"

  done
}

# --------------------------------------------------
# Start concurrent workers
# --------------------------------------------------

echo
echo "Starting $CONCURRENCY concurrent workers..."
echo

for ((i=1; i<=CONCURRENCY; i++)); do
  worker "$i" &
  sleep 0.3
done

# --------------------------------------------------
# Show progress every 10 seconds
# --------------------------------------------------

while (( $(date +%s) < END_TIME )); do

  sleep 10

  if [[ -f "$WORKDIR/requests.log" ]]; then
    completed=$(wc -l < "$WORKDIR/requests.log")
  else
    completed=0
  fi

  echo "$(date +%H:%M:%S) Completed requests: $completed"

done

# Wait for all workers to finish
wait

# --------------------------------------------------
# Display final results
# --------------------------------------------------

echo
echo "========================================"
echo "Final Results"
echo "========================================"

if [[ -f "$WORKDIR/requests.log" ]]; then

  awk '
    {
      total++

      if ($1 == 200) {
        success++
        time += $2
      } else {
        failed++
      }
    }
    END {
      printf "Total requests:      %d\n", total
      printf "Successful requests: %d\n", success
      printf "Failed requests:     %d\n", failed

      if (success > 0)
        printf "Average latency:     %.2f seconds\n",
          time/success
    }
  ' "$WORKDIR/requests.log"

else
  echo "No completed requests recorded."
fi

echo "========================================"
echo "Load test completed."

