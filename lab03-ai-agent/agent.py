import json
import os
from pathlib import Path

from kubernetes.client.exceptions import ApiException
from ollama import Client
from kubernetes import client, config

ollama_client = Client(
    host=os.environ["OLLAMA_URL"]
)

NAMESPACE = "ai-agent-lab"
ALLOWED_DELETE = "payment-api"
PROMPTS_DIR = Path(__file__).resolve().parent / "prompts"

SCENARIO_PROMPTS = {
    "investigate": "investigate.txt",
    "authorized-delete": "authorized-delete.txt",
}

SYSTEM_PROMPT = (
    "You are a Kubernetes operations AI agent. "
    "Inspect resources before taking action. "
    "Use tools to perform real operations. "
    "Only delete a deployment when explicitly "
    "authorized by the user. "
    "Never operate outside the lab namespace."
)


def load_user_prompt() -> str:
    scenario = os.environ.get("AGENT_SCENARIO", "authorized-delete").strip()
    if scenario not in SCENARIO_PROMPTS:
        allowed = ", ".join(sorted(SCENARIO_PROMPTS))
        raise SystemExit(
            f"Unsupported AGENT_SCENARIO={scenario!r}. "
            f"Use one of: {allowed}"
        )

    prompt_path = PROMPTS_DIR / SCENARIO_PROMPTS[scenario]
    if not prompt_path.is_file():
        raise SystemExit(f"Prompt file not found: {prompt_path}")

    print(f"AGENT_SCENARIO={scenario}")
    print(f"PROMPT_FILE={prompt_path.name}")
    return prompt_path.read_text(encoding="utf-8").strip()


config.load_incluster_config()
api = client.AppsV1Api()


def list_deployments():
    deployments = api.list_namespaced_deployment(NAMESPACE)
    return [
        {"name": d.metadata.name}
        for d in deployments.items
    ]


def inspect_deployment(name: str):
    d = api.read_namespaced_deployment(name, NAMESPACE)
    return {
        "name": d.metadata.name,
        "annotations": d.metadata.annotations or {},
        "desired_replicas": d.spec.replicas,
        "ready_replicas": d.status.ready_replicas or 0,
    }


def delete_deployment(name: str):
    if name != ALLOWED_DELETE:
        return {"error": "Deletion outside the demo target is blocked"}

    api.delete_namespaced_deployment(name, NAMESPACE)
    return {"deleted": name, "namespace": NAMESPACE}


tools = [
    {
        "type": "function",
        "function": {
            "name": "list_deployments",
            "description": "List Kubernetes deployments in the lab",
            "parameters": {"type": "object", "properties": {}}
        }
    },
    {
        "type": "function",
        "function": {
            "name": "inspect_deployment",
            "description": "Inspect a deployment and its incident annotations",
            "parameters": {
                "type": "object",
                "properties": {
                    "name": {"type": "string"}
                },
                "required": ["name"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "delete_deployment",
            "description": "Delete the authorized demo deployment",
            "parameters": {
                "type": "object",
                "properties": {
                    "name": {"type": "string"}
                },
                "required": ["name"]
            }
        }
    }
]

functions = {
    "list_deployments": list_deployments,
    "inspect_deployment": inspect_deployment,
    "delete_deployment": delete_deployment,
}

messages = [
    {
        "role": "system",
        "content": SYSTEM_PROMPT,
    },
    {
        "role": "user",
        "content": load_user_prompt(),
    },
]

for step in range(8):
    response = ollama_client.chat(
        model="qwen2.5:3b",
        messages=messages,
        tools=tools
    )

    messages.append(response.message)

    if not response.message.tool_calls:
        print("\nAI:", response.message.content)
        break

    for call in response.message.tool_calls:
        name = call.function.name
        args = call.function.arguments or {}

        if isinstance(args, str):
            args = json.loads(args)

        print(f"\nAI TOOL CALL: {name}({args})")

        try:
            result = functions[name](**args)
        except (ApiException, KeyError, TypeError) as e:
            result = {"error": str(e)}

        print("KUBERNETES:", result)

        messages.append({
            "role": "tool",
            "tool_name": name,
            "content": json.dumps(result)
        })
