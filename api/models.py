from datetime import datetime

from pydantic import BaseModel, Field


class ItemBase(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=1000)
    status: str = Field(default="Open", max_length=40)


class ItemCreate(ItemBase):
    pass


class ItemUpdate(ItemBase):
    pass


class Item(ItemBase):
    id: int
    created_by: str
    created_at: datetime
    updated_by: str | None
    updated_at: datetime | None
