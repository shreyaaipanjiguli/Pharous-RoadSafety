"""add corridor identity to road segments"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "bf29db10b532"
down_revision: Union[str, Sequence[str], None] = "b7c42a91d603"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Create the corridor registry.
    op.create_table(
        "corridors",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("name", sa.String(150), nullable=False, unique=True),
        sa.Column("highway_code", sa.String(50), nullable=True),
    )

    # Register the existing supported corridor.
    op.execute(
        sa.text(
            """
            INSERT INTO corridors (name, highway_code)
            VALUES ('Shiradi Ghat', 'NH-75')
            """
        )
    )

    # Add nullable first so existing rows can be backfilled safely.
    op.add_column(
        "road_segments",
        sa.Column("corridor_id", sa.Integer(), nullable=True),
    )

    op.execute(
        sa.text(
            """
            UPDATE road_segments
            SET corridor_id = (
                SELECT id FROM corridors WHERE name = 'Shiradi Ghat'
            )
            """
        )
    )

    op.alter_column(
        "road_segments",
        "corridor_id",
        existing_type=sa.Integer(),
        nullable=False,
    )

    op.create_foreign_key(
        "fk_road_segments_corridor_id_corridors",
        "road_segments",
        "corridors",
        ["corridor_id"],
        ["id"],
    )

    op.drop_constraint(
        "road_segments_segment_no_key",
        "road_segments",
        type_="unique",
    )

    op.create_unique_constraint(
        "uq_road_segments_corridor_segment_no",
        "road_segments",
        ["corridor_id", "segment_no"],
    )


def downgrade() -> None:
    op.drop_constraint(
        "uq_road_segments_corridor_segment_no",
        "road_segments",
        type_="unique",
    )

    op.create_unique_constraint(
        "road_segments_segment_no_key",
        "road_segments",
        ["segment_no"],
    )

    op.drop_constraint(
        "fk_road_segments_corridor_id_corridors",
        "road_segments",
        type_="foreignkey",
    )

    op.drop_column("road_segments", "corridor_id")
    op.drop_table("corridors")
