#!/usr/bin/env python3
"""Minimal OpenAI-compatible chat client for the cluster's Ollama or vLLM.

Standard library only. Usage: chat.py MODEL PROMPT
Reads the base URL from LLM_URL, falling back to OLLAMA_URL (default
http://localhost:11434), so it works through `kubectl port-forward` to either
engine (examples/vllm sets LLM_URL=http://localhost:8000). Any OpenAI SDK
works the same way with base_url=f"{LLM_URL}/v1" and any API key.
"""

import json
import os
import sys
import time
import urllib.request


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    model, prompt = sys.argv[1], sys.argv[2]
    base = os.environ.get("LLM_URL") or os.environ.get("OLLAMA_URL", "http://localhost:11434")
    base = base.rstrip("/")

    request = urllib.request.Request(
        f"{base}/v1/chat/completions",
        data=json.dumps(
            {"model": model, "messages": [{"role": "user", "content": prompt}]}
        ).encode(),
        headers={
            "Content-Type": "application/json",
            "Authorization": "Bearer none",  # ignored by both engines here, required by the API shape
        },
    )
    started = time.monotonic()
    # First call can include loading the model into VRAM, which takes a while.
    with urllib.request.urlopen(request, timeout=600) as response:
        body = json.load(response)
    elapsed = time.monotonic() - started

    print(body["choices"][0]["message"]["content"])
    usage = body.get("usage", {})
    tokens = usage.get("completion_tokens")
    if tokens:
        print(f"\n[{model}: {tokens} tokens in {elapsed:.1f}s, ~{tokens / elapsed:.1f} tok/s]", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
