import os

PROJECT_ENDPOINT = os.getenv(
    "AZURE_AI_PROJECT_ENDPOINT",
    "https://langchain-academy-resource.services.ai.azure.com/api/projects/langchain-academy",
)

OPENAI_CHAT_MODEL = os.getenv("OPENAI_CHAT_MODEL", "gpt-4o-mini")
DEEPSEEK_CHAT_MODEL = os.getenv("DEEPSEEK_CHAT_MODEL", "DeepSeek-R1")

KNOWLEDGE_BASE_AGENT_NAME = os.getenv("KNOWLEDGE_BASE_AGENT_NAME", "knowledge-base")
KNOWLEDGE_BASE_AGENT_VERSION = os.getenv("KNOWLEDGE_BASE_AGENT_VERSION", "latest")
