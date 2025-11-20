kubectl run llama-cli --rm -it --image=curlimages/curl:8.7.1 --restart=Never -n default --   sh -c '
    curl -s -X POST http://llama-service:8080/completion \
      -H "Content-Type: application/json" \
      -d "{\"prompt\":\"Say hello from Kubernetes with Ceph-backed storage and GPUs.\",\"n_predict\":64}" |
      sed "s/\\n/\n/g" | head -n 10
  '
