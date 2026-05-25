from pathlib import Path
from typing import Annotated, Any

from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from .auth import display_name, require_admin, require_reader
from .config import get_settings
from .database import db_cursor
from .models import Item, ItemCreate, ItemUpdate


settings = get_settings()
BASE_DIR = Path(__file__).resolve().parent.parent
DIST_DIR = BASE_DIR / "dist"

app = FastAPI(title="SQL SSO CRUD API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def row_to_item(row: Any) -> Item:
    return Item(
        id=row.Id,
        title=row.Title,
        description=row.Description,
        status=row.Status,
        created_by=row.CreatedBy,
        created_at=row.CreatedAt,
        updated_by=row.UpdatedBy,
        updated_at=row.UpdatedAt,
    )


@app.get("/api/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/me")
def me(user: Annotated[dict[str, Any], Depends(require_reader)]) -> dict[str, Any]:
    return {
        "name": user.get("name"),
        "username": display_name(user),
        "roles": sorted(user["app_roles"]),
    }


@app.get("/api/items", response_model=list[Item])
def list_items(_: Annotated[dict[str, Any], Depends(require_reader)]) -> list[Item]:
    with db_cursor() as cursor:
        rows = cursor.execute(
            """
            SELECT Id, Title, Description, Status, CreatedBy, CreatedAt, UpdatedBy, UpdatedAt
            FROM dbo.Items
            ORDER BY CreatedAt DESC
            """
        ).fetchall()
    return [row_to_item(row) for row in rows]


@app.post("/api/items", response_model=Item, status_code=status.HTTP_201_CREATED)
def create_item(
    payload: ItemCreate,
    user: Annotated[dict[str, Any], Depends(require_admin)],
) -> Item:
    actor = display_name(user)
    with db_cursor() as cursor:
        row = cursor.execute(
            """
            INSERT INTO dbo.Items (Title, Description, Status, CreatedBy)
            OUTPUT inserted.Id, inserted.Title, inserted.Description, inserted.Status,
                   inserted.CreatedBy, inserted.CreatedAt, inserted.UpdatedBy, inserted.UpdatedAt
            VALUES (?, ?, ?, ?)
            """,
            payload.title,
            payload.description,
            payload.status,
            actor,
        ).fetchone()
    return row_to_item(row)


@app.put("/api/items/{item_id}", response_model=Item)
def update_item(
    item_id: int,
    payload: ItemUpdate,
    user: Annotated[dict[str, Any], Depends(require_admin)],
) -> Item:
    actor = display_name(user)
    with db_cursor() as cursor:
        row = cursor.execute(
            """
            UPDATE dbo.Items
            SET Title = ?, Description = ?, Status = ?, UpdatedBy = ?, UpdatedAt = SYSUTCDATETIME()
            OUTPUT inserted.Id, inserted.Title, inserted.Description, inserted.Status,
                   inserted.CreatedBy, inserted.CreatedAt, inserted.UpdatedBy, inserted.UpdatedAt
            WHERE Id = ?
            """,
            payload.title,
            payload.description,
            payload.status,
            actor,
            item_id,
        ).fetchone()

    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Item not found")
    return row_to_item(row)


@app.delete("/api/items/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_item(
    item_id: int,
    _: Annotated[dict[str, Any], Depends(require_admin)],
) -> None:
    with db_cursor() as cursor:
        cursor.execute("DELETE FROM dbo.Items WHERE Id = ?", item_id)
        if cursor.rowcount == 0:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Item not found")

if DIST_DIR.exists():
    app.mount("/assets", StaticFiles(directory=DIST_DIR / "assets"), name="assets")

    @app.get("/{full_path:path}")
    def serve_react_app(full_path: str):
        requested_path = DIST_DIR / full_path
        if requested_path.is_file():
            return FileResponse(requested_path)
        return FileResponse(DIST_DIR / "index.html")
