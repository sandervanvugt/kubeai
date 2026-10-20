# CHANGE "localhost" in the curl request to the IP address used by the 
# vllm service

curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen2.5-1.5B-Instruct",
    "messages": [
      {
        "role": "user",
        "content": "Explain Kubernetes in 50 words"
      }
    ],
    "max_tokens": 100
  }'
