
kubectl run llama-cli --rm -it --image=curlimages/curl:8.7.1 --restart=Never -- \
  sh -c '
    curl -s -X POST http://llama-service:8080/completion \
      -H "Content-Type: application/json" \
      -d "{\"prompt\":\"Say hello from Kubernetes and mention GPUs.\",\"n_predict\":64}" |
      sed "s/\\n/\n/g" | head -n 10
  '

