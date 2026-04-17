#!/usr/bin/env bash

kubectl run llama-load --rm -it \
  --image=curlimages/curl:8.7.1 --restart=Never -- \
  sh -c '
    DURATION=90      # seconds
    CONCURRENCY=8    # requests in parallel
    END=$(( $(date +%s) + DURATION ))

    echo "Starting load: ${DURATION}s, concurrency=${CONCURRENCY}"
    echo "Target: http://llama-service:8080/completion"

    while :; do
      NOW=$(date +%s)
      [ "$NOW" -ge "$END" ] && break

      echo "Wave at $(date)..."

      i=0
      while [ "$i" -lt "$CONCURRENCY" ]; do
        i=$((i+1))
        (
          # Send one heavy request
          cat <<EOF | curl -s -X POST http://llama-service:8080/completion \
            -H "Content-Type: application/json" \
            --data-binary @- > /dev/null
{
  "prompt": "You are a large language model running on Kubernetes on NVIDIA RTX 4070 GPUs with time-slicing enabled. Generate a long, detailed technical explanation about optimizing LLM inference on GPU-enabled clusters. Include topics such as GPU operators, device plugins, timeslicing vs MIG, pod requests/limits, HPA, and Gateway API-based ingress. Be verbose and do not stop early.",
  "n_predict": 768,
  "temperature": 0.7
}
EOF
        ) &
      done

      # Wait for this wave of requests to finish before starting the next
      wait
    done

    echo "Load test complete."
  '

