from fastapi import FastAPI

from app.api.router import api_router

app = FastAPI(
    title="Email Assistant API",
    version="1.0.0",
    description="API for classifying, analyzing, and drafting responses for incoming emails.",
)

app.include_router(api_router)


@app.get("/health", tags=["health"])
def health_check() -> dict[str, str]:
    return {"status": "ok"}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
