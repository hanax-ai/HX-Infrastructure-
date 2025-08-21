from fastapi import FastAPI, Request
from starlette.responses import JSONResponse

app = FastAPI()

@app.get("/healthz")
async def health_check():
    return JSONResponse({"ok": True})

