import json
import re
from typing import Literal

from azure.identity import DefaultAzureCredential
from langchain_azure_ai.agents import AgentServiceFactory
from langchain_azure_ai.chat_models import AzureAIOpenAIApiChatModel
from langchain_core.messages import (
    AIMessage,
    BaseMessage,
    HumanMessage,
    SystemMessage,
    ToolMessage,
)
from langchain_core.tools import tool
from langgraph.graph import END, START, StateGraph
from langgraph.prebuilt import ToolNode

from app.core.settings import (
    DEEPSEEK_CHAT_MODEL,
    KNOWLEDGE_BASE_AGENT_NAME,
    KNOWLEDGE_BASE_AGENT_VERSION,
    OPENAI_CHAT_MODEL,
    PROJECT_ENDPOINT,
)
from app.models.email import (
    AnalysisResult,
    ClassifyResult,
    EmailState,
    InputState,
    OutputState,
    TemplateResult,
)
from app.prompts.email_prompts import (
    ANALYZER_SYSTEM,
    CLASSIFY_SYSTEM,
    ORCHESTRATOR_SYSTEM,
    REPLY_SYSTEM,
)


llm = AzureAIOpenAIApiChatModel(
    project_endpoint=PROJECT_ENDPOINT,
    credential=DefaultAzureCredential(),
    model=OPENAI_CHAT_MODEL,
)

llm_deepseek = AzureAIOpenAIApiChatModel(
    project_endpoint=PROJECT_ENDPOINT,
    credential=DefaultAzureCredential(),
    model=DEEPSEEK_CHAT_MODEL,
)

factory = AgentServiceFactory(
    project_endpoint=PROJECT_ENDPOINT,
    credential=DefaultAzureCredential(),
)
knowledge_base_agent_node = factory.get_agent_node(
    name=KNOWLEDGE_BASE_AGENT_NAME,
    version=KNOWLEDGE_BASE_AGENT_VERSION,
)


@tool
def classify_and_summarize(subject: str, title: str, content: str) -> str:
    """Classify the email (Spam / Normal / Urgent) and produce a concise 1-2 sentence summary."""
    structured_llm = llm.with_structured_output(ClassifyResult, include_raw=False)
    result = structured_llm.invoke(
        [
            SystemMessage(content=CLASSIFY_SYSTEM),
            HumanMessage(
                content=f"Subject: {subject}\nTitle: {title}\nContent: {content}"
            ),
        ]
    )
    data = ClassifyResult.model_validate(result).model_dump()
    return json.dumps(data)


@tool
def analyze_email_content(
    subject: str, content: str, classification: str, summary: str
) -> str:
    """Analyze the email for key signals, risks, and the recommended handling approach."""
    structured_llm = llm.with_structured_output(AnalysisResult, include_raw=False)
    result = structured_llm.invoke(
        [
            SystemMessage(content=ANALYZER_SYSTEM),
            HumanMessage(
                content=(
                    f"Classification: {classification}\n"
                    f"Summary: {summary}\n"
                    f"Subject: {subject}\n"
                    f"Content: {content}"
                )
            ),
        ]
    )
    data = AnalysisResult.model_validate(result).model_dump()
    return json.dumps(data)


@tool
def get_recommended_actions(classification: str) -> str:
    """Return the recommended action list for the given email classification."""
    action_map: dict[str, list[str]] = {
        "Spam": ["move_to_spam_folder"],
        "Normal": ["route_to_inbox_queue"],
        "Urgent": ["escalate_to_on_call", "notify_team_channel", "flag_for_review"],
    }
    actions = action_map.get(classification, ["route_to_inbox_queue"])
    return json.dumps({"actions": actions})


WORKER_TOOLS = [
    classify_and_summarize,
    analyze_email_content,
    get_recommended_actions,
]

tool_node = ToolNode(WORKER_TOOLS)


def _extract_tool_results(messages: list[BaseMessage]) -> dict[str, dict]:
    id_to_name: dict[str, str] = {}
    for msg in messages:
        if isinstance(msg, AIMessage) and getattr(msg, "tool_calls", None):
            for tc in msg.tool_calls:
                id_to_name[tc["id"]] = tc["name"]

    tool_results: dict[str, dict] = {}
    for msg in messages:
        if isinstance(msg, ToolMessage):
            name = id_to_name.get(msg.tool_call_id)
            if name:
                try:
                    tool_results[name] = json.loads(msg.content)
                except (json.JSONDecodeError, TypeError):
                    tool_results[name] = {"raw": str(msg.content)}
    return tool_results


def orchestrator_node(state: EmailState):
    llm_with_tools = llm.bind_tools(WORKER_TOOLS)
    messages = list(state.get("messages") or [])

    if not messages:
        messages = [
            HumanMessage(
                content=(
                    "Process this email:\n"
                    f"Subject: {state['subject']}\n"
                    f"Title: {state['title']}\n"
                    f"Content: {state['content']}"
                )
            )
        ]

    response = llm_with_tools.invoke(
        [SystemMessage(content=ORCHESTRATOR_SYSTEM)] + messages
    )
    return {"messages": [response]}


def knowledge_base_node(state: EmailState):
    messages = list(state.get("messages") or [])
    tool_results = _extract_tool_results(messages)
    classify = tool_results.get("classify_and_summarize", {})

    classification = classify.get("classification")
    summary = classify.get("summary")
    if not classification or not summary:
        raise ValueError(
            "KnowledgeBaseNode requires classification and summary from tool results."
        )

    kb_query = (
        f"Classification: {classification}\n"
        f"Summary: {summary}\n"
        f"Subject: {state['subject']}\n"
        f"Title: {state['title']}\n"
        f"Content: {state['content']}\n\n"
    )

    kb_response = knowledge_base_agent_node.invoke(
        {"messages": [HumanMessage(content=kb_query)]}
    )

    pending_type = None
    if isinstance(kb_response, dict):
        pending_type = kb_response.get("azure_ai_agents_pending_type")
        if not pending_type and isinstance(kb_response.get("messages"), dict):
            pending_type = kb_response["messages"].get("azure_ai_agents_pending_type")

    if pending_type == "mcp_approval":
        ai_msg = kb_response.get("messages") if isinstance(kb_response, dict) else None
        if not isinstance(ai_msg, AIMessage) or not getattr(ai_msg, "tool_calls", None):
            raise ValueError(
                "knowledge-base agent pending approval but no tool_call was returned."
            )

        approval_call_id = ai_msg.tool_calls[0]["id"]
        kb_response = knowledge_base_agent_node.invoke(
            {
                "messages": [
                    ToolMessage(
                        content='{"approve": true}', tool_call_id=approval_call_id
                    )
                ],
                "azure_ai_agents_conversation_id": kb_response.get(
                    "azure_ai_agents_conversation_id"
                ),
                "azure_ai_agents_previous_response_id": kb_response.get(
                    "azure_ai_agents_previous_response_id"
                ),
                "azure_ai_agents_pending_type": kb_response.get(
                    "azure_ai_agents_pending_type"
                ),
            }
        )

    kb_messages = (
        kb_response.get("messages", [])
        if isinstance(kb_response, dict)
        else kb_response
    )
    if isinstance(kb_messages, dict):
        ai_payload = kb_messages.get("AIMessage")
        if isinstance(ai_payload, dict):
            template_text = ai_payload.get("content", "")
            if not template_text or not str(template_text).strip():
                raise ValueError(
                    "knowledge-base agent returned empty content after approval."
                )
            return {
                "email_template": TemplateResult(
                    template=str(template_text).strip()
                ).template
            }
        raise ValueError(
            "knowledge-base agent returned an unexpected dict message shape."
        )

    if isinstance(kb_messages, BaseMessage):
        last_msg = kb_messages
    elif isinstance(kb_messages, list):
        if not kb_messages:
            raise ValueError("knowledge-base agent returned no messages.")
        last_msg = kb_messages[-1]
    else:
        raise ValueError("knowledge-base agent returned an unexpected response shape.")

    template_text = last_msg.content
    if isinstance(template_text, list):
        template_text = " ".join(
            block.get("text", "") if isinstance(block, dict) else str(block)
            for block in template_text
        ).strip()

    return {"email_template": TemplateResult(template=template_text).template}


def synthesizer_node(state: EmailState):
    messages = list(state.get("messages") or [])

    tool_results = _extract_tool_results(messages)
    classify = tool_results.get("classify_and_summarize", {})
    analysis = tool_results.get("analyze_email_content", {})
    actions = tool_results.get("get_recommended_actions", {})
    template_text = state.get("email_template")

    missing = []
    if not classify.get("summary"):
        missing.append("summary")
    if not classify.get("classification"):
        missing.append("classification")
    if not analysis.get("analysis"):
        missing.append("analysis")
    if not template_text:
        missing.append("template")
    if missing:
        raise ValueError(
            f"Synthesizer: missing required fields from workers: {missing}"
        )

    classification = classify["classification"]
    summary = classify["summary"]
    if classification == "Spam":
        reply_message = "No reply generated."
    else:
        raw_response = llm_deepseek.invoke(
            [
                SystemMessage(
                    content=(
                        f"{REPLY_SYSTEM}\n\n"
                        f"Classification: {classification}\n"
                        f"Summary: {summary}\n"
                        f"Template Guidance:\n{template_text}"
                    )
                ),
                HumanMessage(
                    content=(
                        f"Subject: {state['subject']}\n"
                        f"Original Content: {state['content']}\n\n"
                        "Draft the reply now. Return only plain reply text."
                    )
                ),
            ]
        )
        raw = raw_response.content
        if isinstance(raw, list):
            raw = " ".join(
                block.get("text", "") if isinstance(block, dict) else str(block)
                for block in raw
            )
        reply_message = re.sub(r"<think>.*?</think>", "", raw, flags=re.DOTALL).strip()

    return {
        "summary": summary,
        "classification": classification,
        "analysis": analysis["analysis"],
        "email_template": template_text,
        "actions": actions.get("actions", []),
        "final_message": reply_message,
    }


def should_continue(state: EmailState) -> Literal["tools", "KnowledgeBaseNode"]:
    last = state["messages"][-1]
    if isinstance(last, AIMessage) and getattr(last, "tool_calls", None):
        return "tools"
    return "KnowledgeBaseNode"


def build_graph():
    builder = StateGraph(EmailState)

    builder.add_node("Orchestrator", orchestrator_node)
    builder.add_node("tools", tool_node)
    builder.add_node("KnowledgeBaseNode", knowledge_base_node)
    builder.add_node("Synthesizer", synthesizer_node)

    builder.add_edge(START, "Orchestrator")
    builder.add_conditional_edges("Orchestrator", should_continue)
    builder.add_edge("tools", "Orchestrator")
    builder.add_edge("KnowledgeBaseNode", "Synthesizer")
    builder.add_edge("Synthesizer", END)

    return builder.compile()


graph = build_graph()


def run_email_workflow(email_payload: dict) -> dict:
    validated_input = InputState.model_validate(email_payload)
    initial_state: EmailState = {
        **validated_input.model_dump(),
        "messages": [],
        "summary": None,
        "classification": None,
        "analysis": None,
        "email_template": None,
        "actions": [],
        "final_message": None,
    }
    result = graph.invoke(initial_state)
    return OutputState.model_validate(
        {
            "summary": result["summary"],
            "classification": result["classification"],
            "analysis": result["analysis"],
            "actions": result["actions"],
            "message": result["final_message"],
        }
    ).model_dump()
