"""
SQLAlchemy engine + session setup, pointed at Supabase Postgres via the
pooled connection string in .env.

`get_db()` is a FastAPI dependency: every route that touches the database
takes `db: Session = Depends(get_db)` as a parameter, and FastAPI handles
opening/closing the session around the request automatically.
"""

from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

from app.config import settings

engine = create_engine(
    settings.database_url,
    pool_pre_ping=True,  # avoids "server closed the connection unexpectedly"
                         # errors from stale pooled connections
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
