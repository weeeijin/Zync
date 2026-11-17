import httpx
import json
import logging
import time
from typing import AsyncGenerator
from config import GLM_API_KEY, GLM_URL, GLM_MODEL
from observability import LLM_FIRST_TOKEN, record_llm_usage, track_llm_call

logger = logging.getLogger("zync.llm")

HEADERS = {
    "Authorization": f"Bearer {GLM_API_KEY}",
    "Content-Type": "application/json",
}


def _build_payload(
    system_prompt: str,
    user_message: str,
    tools: list = None,
    images: list = None,
    stream: bool = False,
    json_mode: bool = False,
) -> dict:
    """Build the request payload for GLM API."""

    # Default: plain text message
    content = user_message

    # Multimodal: attach images if provided
    if images:
        content = [
            {"type": "image_url", "image_url": {"url": img}}
            for img in images
        ] + [{"type": "text", "text": user_message}]

    payload = {
        "model": GLM_MODEL,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user",   "content": content},
        ],
        "temperature": 0.1,   # Low = deterministic, good for engineering
        "stream": stream,
    }

    # Force structured JSON output (used by Agent 2, 4, 5)
    if json_mode:
        payload["response_format"] = {"type": "json_object"}

    # Attach function-calling tools (used by Agent 2 lixiviant KB lookup)
    if tools:
        payload["tools"] = tools

    return payload


# ─── 1. Single call (no streaming) ───────────────────────────────────────────

async def call_glm(
    system_prompt: str,
    user_message: str,
    tools: list = None,
    images: list = None,
    json_mode: bool = False,
) -> dict:
    """
    Single GLM call. Returns:
    {
        "output":    str,   # final answer text or JSON string
        "reasoning": str,   # GLM's internal thinking trace (XAI block)
        "tool_calls": list  # if GLM called a function tool
    }
    """
    payload = _build_payload(
        system_prompt, user_message,
        tools=tools, images=images,
        stream=False, json_mode=json_mode,
    )

    with track_llm_call("call", GLM_MODEL):
        async with httpx.AsyncClient(timeout=120) as client:
            res = await client.post(GLM_URL, json=payload, headers=HEADERS)
            res.raise_for_status()
            data = res.json()
    record_llm_usage(GLM_MODEL, data.get("usage"))

    message = data["choices"][0]["message"]

    return {
        "output":     message.get("content", ""),
        "reasoning":  message.get("reasoning_content", ""),  # XAI trace
        "tool_calls": message.get("tool_calls", []),
    }


# ─── 2. Streaming call ────────────────────────────────────────────────────────

async def stream_glm(
    system_prompt: str,
    user_message: str,
    tools: list = None,
    images: list = None,
    json_mode: bool = False,
) -> AsyncGenerator[dict, None]:
    """
    Streaming GLM call. Yields chunks as they arrive:

    Reasoning chunk  → {"type": "reasoning", "text": "..."}
    Answer chunk     → {"type": "output",    "text": "..."}
    Final chunk      → {"type": "done",      "output": full_text,
                                              "reasoning": full_reasoning}
    Error chunk      → {"type": "error",     "message": "..."}

    Usage (in agent):
        async for chunk in stream_glm(system, message):
            yield chunk   # forward straight to SSE route
    """
    payload = _build_payload(
        system_prompt, user_message,
        tools=tools, images=images,
        stream=True, json_mode=json_mode,
    )

    try:
        with track_llm_call("stream", GLM_MODEL):
            async for chunk in _stream_chunks(payload):
                yield chunk
    except httpx.HTTPStatusError as e:
        logger.warning("GLM API returned HTTP %s", e.response.status_code)
        yield {"type": "error", "message": f"GLM API error: {e.response.status_code}"}
    except httpx.TimeoutException:
        logger.warning("GLM API timed out")
        yield {"type": "error", "message": "GLM API timeout — model took too long"}
    except Exception:
        # Full details go to the logs only — never to the client
        logger.exception("GLM streaming call failed")
        yield {"type": "error", "message": "GLM request failed — please try again"}


async def _stream_chunks(payload: dict) -> AsyncGenerator[dict, None]:
    """Raw SSE parsing for stream_glm; raises on transport/HTTP errors."""
    full_output    = ""
    full_reasoning = ""
    started        = time.perf_counter()
    first_token    = True

    async with httpx.AsyncClient(timeout=180) as client:
        async with client.stream(
            "POST", GLM_URL, json=payload, headers=HEADERS
        ) as response:
            response.raise_for_status()

            async for line in response.aiter_lines():
                if not line.startswith("data: "):
                    continue

                raw = line[6:].strip()

                if raw == "[DONE]":
                    # Final chunk — send complete assembled output
                    yield {
                        "type":      "done",
                        "output":    full_output,
                        "reasoning": full_reasoning,
                    }
                    return

                try:
                    chunk = json.loads(raw)
                except json.JSONDecodeError:
                    continue

                # GLM reports token usage on the last chunk
                record_llm_usage(GLM_MODEL, chunk.get("usage"))

                choices = chunk.get("choices") or [{}]
                delta = choices[0].get("delta", {})

                reasoning_delta = delta.get("reasoning_content", "")
                output_delta = delta.get("content", "")

                if first_token and (reasoning_delta or output_delta):
                    LLM_FIRST_TOKEN.labels(model=GLM_MODEL).observe(time.perf_counter() - started)
                    first_token = False

                # Reasoning trace (thinking mode — XAI block)
                if reasoning_delta:
                    full_reasoning += reasoning_delta
                    yield {"type": "reasoning", "text": reasoning_delta}

                # Answer text
                if output_delta:
                    full_output += output_delta
                    yield {"type": "output", "text": output_delta}


# ─── 3. Tool call helper ──────────────────────────────────────────────────────

async def call_glm_with_tools(
    system_prompt: str,
    user_message: str,
    tools: list,
    tool_executor,          # async fn(tool_name, tool_args) → str
) -> dict:
    """
    Multi-turn tool use loop:
    1. Call GLM with tools defined
    2. If GLM calls a tool → execute it → send result back
    3. Repeat until GLM gives final answer (no more tool calls)

    Returns same shape as call_glm().
    """
    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user",   "content": user_message},
    ]

    async with httpx.AsyncClient(timeout=120) as client:
        for _ in range(5):  # Max 5 tool-call rounds
            payload = {
                "model":       GLM_MODEL,
                "messages":    messages,
                "temperature": 0.1,
                "tools":       tools,
            }

            with track_llm_call("tools", GLM_MODEL):
                res = await client.post(GLM_URL, json=payload, headers=HEADERS)
                res.raise_for_status()
                data = res.json()
            record_llm_usage(GLM_MODEL, data.get("usage"))

            message = data["choices"][0]["message"]
            messages.append(message)  # Add assistant turn to history

            # No tool calls → GLM gave final answer
            if not message.get("tool_calls"):
                return {
                    "output":     message.get("content", ""),
                    "reasoning":  message.get("reasoning_content", ""),
                    "tool_calls": [],
                }

            # Execute each tool call and feed results back
            for tool_call in message["tool_calls"]:
                tool_name = tool_call["function"]["name"]
                tool_args = json.loads(tool_call["function"]["arguments"])

                tool_result = await tool_executor(tool_name, tool_args)

                messages.append({
                    "role":         "tool",
                    "tool_call_id": tool_call["id"],
                    "content":      str(tool_result),
                })

    # Fallback if loop exhausted
    return {"output": "", "reasoning": "", "tool_calls": []}