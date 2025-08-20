import os
from fastapi import FastAPI
from services.postgres_service import PostgresService
from services.redis_service import RedisService
from services.qdrant_service import QdrantService
from middlewares.db_guard import DbGuardMiddleware

def build_app() -> FastAPI:
    app = FastAPI(title="HX Gateway Wrapper")
    pg = PostgresService(os.getenv("PG_URL"))
    rd = RedisService(os.getenv("REDIS_URL"))
    qd = QdrantService(os.getenv("QDRANT_URL"))

    guarded = ("/v1/keys", "/v1/api_keys", "/v1/teams", "/v1/users", "/v1/tenants")
    dbguard = DbGuardMiddleware(pg, rd, guarded)

    # Example middleware pipeline pattern
    @app.middleware("http")
    async def pipeline(request, call_next):
        ctx = {"request": request}
        ctx = await dbguard.process(ctx)
        return await call_next(request)

    @app.get("/healthz/deps")
    async def deps():
        return {
            "postgres": await pg.healthy(),
            "redis": await rd.healthy(),
            "qdrant": await qd.healthy(),
        }
    return app
