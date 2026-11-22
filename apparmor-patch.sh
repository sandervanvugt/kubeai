kubectl patch deployment vllm \
  -n genai \
  --type=strategic \
  -p '{"spec":{"template":{"spec":{"securityContext":{"appArmorProfile":{"type":"Unconfined"}}}}}}'
