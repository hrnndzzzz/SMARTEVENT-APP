"""
POST /auth/register  — creates a user (admin, adviser, or officer)
POST /auth/login      — verifies credentials, returns a JWT
GET  /auth/me          — returns the currently logged-in user (proves
                          the token flow works end-to-end)

/auth/register requires an existing admin's token (require_role("admin")).
This means there is no self-service way to create the very first admin
account through the API — that's intentional, not an oversight. The
first admin is created with a one-off manual INSERT directly in
Supabase's SQL editor:

    INSERT INTO users (id, full_name, email, password_hash, role, is_active)
    VALUES (
        gen_random_uuid(),
        'Your Name',
        'admin@example.com',
        '<a real Argon2 hash — see note below>',
        'admin',
        true
    );

The tricky part is password_hash: it must be a real Argon2 hash, not
plain text — you can't type a plain password directly into that column
and expect login to work. Easiest way to generate one: run this once
locally in the venv (with pwdlib installed):

    python -c "from pwdlib import PasswordHash; print(PasswordHash.recommended().hash('yourpassword'))"

then paste the printed hash as the password_hash value in the INSERT
above. After that one manual row exists, every subsequent account is
created normally through POST /auth/register using that admin's token.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user, require_role
from app.models import User
from app.schemas import Token, UserCreate, UserOut
from app.security import create_access_token, hash_password, verify_password

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=UserOut, status_code=status.HTTP_201_CREATED)
def register(
    payload: UserCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("admin")),
):
    existing = db.query(User).filter(User.email == payload.email).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A user with this email already exists",
        )

    user = User(
        full_name=payload.full_name,
        email=payload.email,
        password_hash=hash_password(payload.password),
        role=payload.role,
        position=payload.position,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


@router.post("/login", response_model=Token)
def login(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    # OAuth2PasswordRequestForm sends the email in its `username` field —
    # that's just the standard OAuth2 form shape, not a schema mismatch.
    user = db.query(User).filter(User.email == form_data.username).first()

    if not user or not verify_password(form_data.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This account has been deactivated",
        )

    access_token = create_access_token(subject=str(user.id))
    return Token(access_token=access_token)


@router.get("/me", response_model=UserOut)
def read_current_user(current_user: User = Depends(get_current_user)):
    return current_user
