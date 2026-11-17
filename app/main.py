from __future__ import annotations

import os
import re
import secrets
from contextlib import asynccontextmanager
from datetime import datetime
from time import perf_counter
from urllib.parse import urlparse

import redis.asyncio as redis
from fastapi import FastAPI, HTTPException, Request, Response, status
from fastapi.responses import RedirectResponse
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from pydantic import BaseModel, Field, HttpUrl
from sqlalchemy import DateTime, Integer, String, func, select, update
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

DATABASE_URL = os.getenv(
    "DATABASE_URL", "postgresql+asyncpg://shortener:shortener@postgres:5432/shortener"
)
REDIS_URL = os.getenv("REDIS_URL", "redis://redis:6379/0")
PUBLIC_BASE_URL = os.getenv("PUBLIC_BASE_URL", "http://localhost:8080").rstrip("/")
CACHE_TTL_SECONDS = int(os.getenv("CACHE_TTL_SECONDS", "3600"))
SLUG_PATTERN = re.compile(r"^[A-Za-z0-9_-]{4,32}$")

engine = create_async_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = async_sessionmaker(engine, expire_on_commit=False)
cache: redis.Redis | None = None

REQUESTS = Counter(
    "url_shortener_http_requests_total",
    "HTTP requests",
    ["method", "path", "status"],
)
REQUEST_LATENCY = Histogram(
    "url_shortener_http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "path"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10),
)
REDIRECTS = Counter("url_shortener_redirects_total", "Successful short URL redirects")


class Base(DeclarativeBase):
    pass


class Link(Base):
    __tablename__ = "links"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    slug: Mapped[str] = mapped_column(String(32), unique=True, index=True)
    target_url: Mapped[str] = mapped_column(String(2048))
    clicks: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


@asynccontextmanager
async def lifespan(_: FastAPI):
    global cache
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    cache = redis.from_url(REDIS_URL, decode_responses=True)
    await cache.ping()
    yield
    await cache.aclose()
    await engine.dispose()


app = FastAPI(
    title="Cloud-Native URL Shortener & Analytics Platform",
    version="1.0.0",
    description="URL shortening, redirects, and click analytics backed by PostgreSQL and Redis.",
    lifespan=lifespan,
)


@app.middleware("http")
async def count_requests(request: Request, call_next):
    started_at = perf_counter()
    response = await call_next(request)
    route = request.scope.get("route")
    path = getattr(route, "path", request.url.path)
    REQUESTS.labels(request.method, path, str(response.status_code)).inc()
    REQUEST_LATENCY.labels(request.method, path).observe(perf_counter() - started_at)
    return response


class ShortenRequest(BaseModel):
    url: HttpUrl
    custom_code: str | None = Field(
        default=None,
        min_length=4,
        max_length=32,
        pattern=r"^[A-Za-z0-9_-]+$",
    )


class ShortenResponse(BaseModel):
    code: str
    short_url: str
    target_url: str
    created_at: datetime


class AnalyticsResponse(BaseModel):
    code: str
    target_url: str
    clicks: int
    created_at: datetime


async def get_session():
    async with SessionLocal() as session:
        yield session


@app.get("/health", tags=["operations"])
async def health():
    try:
        async with SessionLocal() as session:
            await session.execute(select(1))
        if cache is None:
            raise RuntimeError("Redis client is not initialized")
        await cache.ping()
    except Exception as exc:
        raise HTTPException(
            status_code=503, detail="A required dependency is unavailable"
        ) from exc
    return {
        "status": "healthy",
        "dependencies": {"postgres": "healthy", "redis": "healthy"},
    }


@app.get("/metrics", tags=["operations"], include_in_schema=False)
async def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.post(
    "/api/v1/links",
    response_model=ShortenResponse,
    status_code=status.HTTP_201_CREATED,
    tags=["links"],
)
async def create_link(payload: ShortenRequest):
    parsed = urlparse(str(payload.url))
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise HTTPException(
            status_code=422, detail="Only absolute HTTP(S) URLs are supported"
        )
    async with SessionLocal() as session:
        for _ in range(5):
            slug = (
                payload.custom_code
                or secrets.token_urlsafe(6).replace("-", "a").replace("_", "b")[:8]
            )
            existing = await session.scalar(select(Link.id).where(Link.slug == slug))
            if existing is not None:
                if payload.custom_code:
                    raise HTTPException(
                        status_code=409, detail="Custom code is already in use"
                    )
                continue
            link = Link(slug=slug, target_url=str(payload.url))
            session.add(link)
            try:
                await session.commit()
                await session.refresh(link)
            except Exception:
                await session.rollback()
                if payload.custom_code:
                    raise HTTPException(
                    status_code=409, detail="Custom code is already in use"
                )
                continue
            if cache is not None:
                await cache.set(f"link:{slug}", link.target_url, ex=CACHE_TTL_SECONDS)
            return ShortenResponse(
                code=link.slug,
                short_url=f"{PUBLIC_BASE_URL}/{link.slug}",
                target_url=link.target_url,
                created_at=link.created_at,
            )
    raise HTTPException(
        status_code=503, detail="Could not allocate a unique short code"
    )


@app.get(
    "/api/v1/links/{code}/analytics",
    response_model=AnalyticsResponse,
    tags=["analytics"],
)
async def analytics(code: str):
    if not SLUG_PATTERN.fullmatch(code):
        raise HTTPException(status_code=404, detail="Short link not found")
    async with SessionLocal() as session:
        link = await session.scalar(select(Link).where(Link.slug == code))
        if link is None:
            raise HTTPException(status_code=404, detail="Short link not found")
        return AnalyticsResponse(
            code=link.slug,
            target_url=link.target_url,
            clicks=link.clicks,
            created_at=link.created_at,
        )


@app.get("/{code}", include_in_schema=False)
async def redirect(code: str):
    if not SLUG_PATTERN.fullmatch(code):
        raise HTTPException(status_code=404, detail="Short link not found")
    target = await cache.get(f"link:{code}") if cache is not None else None
    async with SessionLocal() as session:
        if target is None:
            link = await session.scalar(select(Link).where(Link.slug == code))
            if link is None:
                raise HTTPException(status_code=404, detail="Short link not found")
            target = link.target_url
            if cache is not None:
                await cache.set(f"link:{code}", target, ex=CACHE_TTL_SECONDS)
        await session.execute(
            update(Link)
            .where(Link.slug == code)
            .values(clicks=Link.clicks + 1)
        )
        await session.commit()
    REDIRECTS.inc()
    return RedirectResponse(url=target, status_code=status.HTTP_307_TEMPORARY_REDIRECT)
