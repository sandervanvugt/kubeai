for i in {1..5}; do
  curl -s http://localhost:8000/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{
      "model": "Qwen/Qwen2.5-1.5B-Instruct",
      "messages": [
        {
          "role": "user",
          "content": "Explain Kubernetes networking"
        }
      ],
      "max_tokens": 200
    }' > /dev/null &
done
wait
