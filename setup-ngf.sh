kubectl kustomize \
  "https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=v2.9.0" \
  | kubectl apply -f -

helm install ngf \
  oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
  --version 2.9.0 \
  --namespace nginx-gateway \
  --create-namespace \
  --set nginx.service.type=NodePort \
  --set-json 'nginx.service.nodePorts=[{"port":32080,"listenerPort":80}]' \
  --wait \
  --timeout 5m
