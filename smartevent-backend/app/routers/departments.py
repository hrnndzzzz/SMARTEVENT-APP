"""Read-only department lookup for account and roster setup in Swagger."""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import assert_department_scope, require_role
from app.models import Department, User
from app.schemas import DepartmentCreate, DepartmentOut
from app.services.access_audit import record_access_change

router = APIRouter(prefix="/departments", tags=["departments"])


@router.post("", response_model=DepartmentOut, status_code=status.HTTP_201_CREATED)
def create_department(
    payload: DepartmentCreate, db: Session = Depends(get_db),
    current_user: User = Depends(require_role("super_admin")),
):
    code, name = payload.code.strip().upper(), payload.name.strip()
    if not code or not name:
        raise HTTPException(status_code=422, detail="Department code and name cannot be blank")
    if db.query(Department).filter(Department.code == code).first() is not None:
        raise HTTPException(status_code=409, detail="Department code already exists")
    department = Department(code=code, name=name, description=payload.description)
    db.add(department)
    db.flush()
    record_access_change(db, current_user, "department.created", department)
    db.commit()
    db.refresh(department)
    return department


@router.get(
    "",
    response_model=list[DepartmentOut],
    summary="List available departments",
    description=(
        "Admins see only their assigned department. Super_Admin sees all "
        "departments and can use an ID from this list when creating an Admin "
        "account or managing a member roster."
    ),
)
def list_departments(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("admin")),
):
    query = db.query(Department)
    if current_user.role != "super_admin":
        assert_department_scope(current_user, current_user.department_id)
        query = query.filter(Department.id == current_user.department_id)
    return query.order_by(Department.code).all()
