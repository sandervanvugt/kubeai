#!/usr/bin/env bash
# Continuous concurrent load test for Qwen2.5-7B-Instruct on vLLM.
# Usage: ./test-vllm-concurrent-qwen7b.sh [concurrency] [duration_seconds] [max_tokens]
set -u

NAMESPACE="genai"
SERVICE="vllm"
MODEL="Qwen/Qwen2.5-7B-Instruct"
CONCURRENCY="${1:-15}"
DURATION="${2:-300}"
MAX_TOKENS="${3:-600}"

for cmd in kubectl curl awk mktemp; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: '$cmd' is required." >&2; exit 1; }
done
for value in "$CONCURRENCY" "$DURATION" "$MAX_TOKENS"; do
  [[ "$value" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: concurrency, duration, and max_tokens must be positive integers." >&2; exit 1; }
done

if ! kubectl get svc "$SERVICE" -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "ERROR: A Kubernetes Service named '$SERVICE' in namespace '$NAMESPACE' is required." >&2
  echo "Check: kubectl get svc -n $NAMESPACE" >&2
  exit 1
fi
VLLM_SVC_IP=$(kubectl get svc "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}')
if [[ -z "$VLLM_SVC_IP" || "$VLLM_SVC_IP" == "None" ]]; then
  echo "ERROR: Service '$SERVICE' must have a ClusterIP." >&2
  exit 1
fi
VLLM_URL="http://${VLLM_SVC_IP}:8000"

if ! curl -fsS --max-time 10 "$VLLM_URL/health" >/dev/null; then
  echo "ERROR: vLLM is not reachable at $VLLM_URL/health." >&2
  echo "The host running this script must be able to reach the Kubernetes ClusterIP." >&2
  exit 1
fi

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
END_TIME=$(( $(date +%s) + DURATION ))
PROMPTS=(
  "Explain how Kubernetes schedules GPU workloads and manages resources."
  "Describe how transformer inference uses attention and KV caching."
  "Compare vLLM continuous batching with traditional inference serving."
  "Explain how Prometheus and HPA can autoscale GPU inference workloads."
  "Describe Kubernetes storage choices for model weights and caches."
  "Explain the tradeoffs of model parallelism and data parallelism."
)

printf 'vLLM load test | namespace=%s service=%s IP=%s model=%s\n' "$NAMESPACE" "$SERVICE" "$VLLM_SVC_IP" "$MODEL"
printf 'Concurrency=%s Duration=%ss Max tokens=%s\n' "$CONCURRENCY" "$DURATION" "$MAX_TOKENS"

worker() {
  local id="$1" prompt payload result status elapsed
  while (( $(date +%s) < END_TIME )); do
    prompt="${PROMPTS[$((RANDOM % ${#PROMPTS[@]}))]}"
    payload=$(printf '{"model":"%s","messages":[{"role":"user","content":"%s Give a detailed explanation with examples."}],"max_tokens":%d,"temperature":0.8,"ignore_eos":true}' "$MODEL" "$prompt" "$MAX_TOKENS")
    result=$(curl -sS --connect-timeout 5 --max-time 180 \
      -o /dev/null -w '%{http_code} %{time_total}' \
      -H 'Content-Type: application/json' -d "$payload" \
      "$VLLM_URL/v1/chat/completions" 2>/dev/null) || true
    read -r status elapsed <<< "$result"
    printf '%s %s\n' "${status:-000}" "${elapsed:-0}" >> "$WORKDIR/worker-${id}.log"
  done
}

for ((i=1; i<=CONCURRENCY; i++)); do
  worker "$i" &
done

while (( $(date +%s) < END_TIME )); do
  sleep 10
  completed=$(cat "$WORKDIR"/worker-*.log 2>/dev/null | wc -l)
  printf '%s Completed requests: %s\n' "$(date +%H:%M:%S)" "$completed"
done
wait

awk '{total++; if ($1==200) {success++; time+=$2} else {failed++}} END {printf "Total requests: %d\nSuccessful: %d\nFailed: %d\n", total,success,failed; if(success) printf "Average successful latency: %.2f seconds\n", time/success}' "$WORKDIR"/worker-*.log 2>/dev/null

