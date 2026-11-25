from sqlalchemy import Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from ..database import Base


class Corridor(Base):
    __tablename__ = "corridors"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)

    name: Mapped[str] = mapped_column(
        String(150),
        unique=True,
        nullable=False,
    )

    highway_code: Mapped[str | None] = mapped_column(
        String(50),
        nullable=True,
    )
