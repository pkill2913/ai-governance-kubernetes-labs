FROM python:3.12-slim

WORKDIR /app

RUN pip install --no-cache-dir ollama kubernetes

COPY agent.py .
COPY prompts/ ./prompts/

USER 10001

CMD ["python", "-u", "agent.py"]
