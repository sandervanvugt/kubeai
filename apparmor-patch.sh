kubectl patch deployment vllm-gateway-nginx \
  -n genai \
  --type=strategic \
  -p '{"spec":{"template":{"spec":{"securityContext":{"appArmorProfile":{"type":"Unconfined"}}}}}}'
