from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app import config
from app.routers import modbus_router
from app.services import state_store


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 启动即确保 state.json 存在；上次写入损坏时自动回退示例数据
    state_store.load()
    yield


app = FastAPI(title="Modbus 工业协议数据采集监控", version="1.0.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=config.cors_origins(),
    allow_methods=["*"],
    allow_headers=["*"],
)
app.include_router(modbus_router.router, prefix="/api")


@app.get("/api/health")
def health():
    return {"status": "ok"}
