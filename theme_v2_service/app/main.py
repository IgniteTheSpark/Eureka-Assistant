from fastapi import FastAPI


app = FastAPI(title="Eureka Theme V2 API", version="2.0.0")


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "service": "theme-v2"}
