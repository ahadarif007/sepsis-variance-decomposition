from contextlib import asynccontextmanager

from fastapi import FastAPI

from .db.database import get_engine, Base
from .routers import observations, patients


@asynccontextmanager
async def lifespan(app: FastAPI):
    engine = get_engine()
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield
    await engine.dispose()


app = FastAPI(
    title="SepsisNet",
    description="Real-time ICU sepsis risk prediction API",
    version="1.0.0",
    lifespan=lifespan,
)

app.include_router(observations.router)
app.include_router(patients.router)


@app.get("/health")
async def health():
    return {"status": "ok", "service": "sepsisnet"}
