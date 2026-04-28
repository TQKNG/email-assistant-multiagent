from fastapi import APIRouter, HTTPException

from app.models.email import InputState, OutputState

router = APIRouter(prefix="/api/v1/email", tags=["email"])


def get_workflow_runner():
    from app.services.email_workflow import run_email_workflow

    return run_email_workflow


@router.post("/process", response_model=OutputState)
def process_email(payload: InputState) -> OutputState:
    try:
        run_email_workflow = get_workflow_runner()
        result = run_email_workflow(payload.model_dump())
        return OutputState.model_validate(result)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Email processing failed: {exc}") from exc
