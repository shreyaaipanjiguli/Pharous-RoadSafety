from geoalchemy2 import Geometry
from sqlalchemy import Float, ForeignKey, Integer, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from ..database import Base


class RoadSegment(Base):
    __tablename__ = "road_segments"

    __table_args__ = (
        UniqueConstraint(
            "corridor_id",
            "segment_no",
            name="uq_road_segments_corridor_segment_no",
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)

    corridor_id: Mapped[int] = mapped_column(
        ForeignKey("corridors.id"),
        nullable=False,
    )

    segment_no: Mapped[int] = mapped_column(Integer, nullable=False)

    geom = mapped_column(
        Geometry(geometry_type="LINESTRING", srid=4326),
        nullable=False,
    )

    length_m: Mapped[float] = mapped_column(Float, nullable=False)
    elevation_start_m: Mapped[float] = mapped_column(Float, nullable=False)
    elevation_end_m: Mapped[float] = mapped_column(Float, nullable=False)
    slope_percent: Mapped[float] = mapped_column(Float, nullable=False)
