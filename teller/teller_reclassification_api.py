from __future__ import annotations
from datetime import date, datetime
from decimal import Decimal
from typing import Dict, List, Literal, Optional
from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import text
from teller.teller_db import get_session


class CategoryOption(BaseModel):
    nys_snw_category_id: int
    level_1: Optional[str] = None
    level_1_name: Optional[str] = None
    level_2: Optional[str] = None
    level_2_name: Optional[str] = None
    level_3: Optional[str] = None
    level_4: Optional[str] = None
    categorization: Optional[str] = None
    applicability: Optional[str] = None
    display_label: str


class TransactionCategory(BaseModel):
    nys_snw_category_id: int
    display_label: str


class TransactionRow(BaseModel):
    transaction_id: str
    account_id: str
    date: date
    amount: Decimal
    description: str
    status: str
    transaction_type_code: Optional[str] = None
    teller_category: Optional[str] = None
    classification: Optional[TransactionCategory] = None


class TransactionListResponse(BaseModel):
    total: int
    items: List[TransactionRow]


class ClassificationMutation(BaseModel):
    transaction_id: str
    nys_snw_category_id: Optional[int] = None


class ClassificationBatchRequest(BaseModel):
    updates: List[ClassificationMutation]


class ClassificationWriteResponse(BaseModel):
    transaction_id: str
    nys_snw_category_id: Optional[int] = None
    type: Literal["user"] = "user"
    updated_at: datetime


class CategoryCountsRow(BaseModel):
    nys_snw_category_id: int
    display_label: str
    assigned_transactions: int


def _display_label(row: Dict[str, object]) -> str:
    parts = [
        row.get("level_1_name") or row.get("level_1"),
        row.get("level_2_name") or row.get("level_2"),
        row.get("level_3"),
        row.get("level_4"),
        row.get("categorization"),
    ]
    return " > ".join(str(v).strip() for v in parts if v and str(v).strip())


def _ensure_exists(session, table: str, column: str, value: object, error: str):
    row = session.execute(text(f"SELECT 1 FROM teller.{table} WHERE {column} = :value LIMIT 1"), {"value": value}).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail=error)


def _write_one(session, transaction_id: str, nys_snw_category_id: Optional[int]) -> ClassificationWriteResponse:
    _ensure_exists(session, "transaction", "transaction_id", transaction_id, f"Unknown transaction_id: {transaction_id}")
    if nys_snw_category_id is None:
        session.execute(text("DELETE FROM teller.transaction_nys_snw_category WHERE transaction_id = :transaction_id"),
                        {"transaction_id": transaction_id})
        session.commit()
        return ClassificationWriteResponse(transaction_id=transaction_id, nys_snw_category_id=None, updated_at=datetime.now())
    _ensure_exists(session, "nys_snw_category", "nys_snw_category_id", nys_snw_category_id,
                   f"Unknown nys_snw_category_id: {nys_snw_category_id}")
    updated = session.execute(text("""
        UPDATE teller.transaction_nys_snw_category
           SET nys_snw_category_id = :nys_snw_category_id, type = 'user', updated_at = CURRENT_TIMESTAMP
         WHERE transaction_id = :transaction_id
     RETURNING updated_at
    """), {"transaction_id": transaction_id, "nys_snw_category_id": nys_snw_category_id}).fetchone()
    if not updated:
        updated = session.execute(text("""
            INSERT INTO teller.transaction_nys_snw_category (transaction_id, nys_snw_category_id, type)
            VALUES (:transaction_id, :nys_snw_category_id, 'user')
         RETURNING updated_at
        """), {"transaction_id": transaction_id, "nys_snw_category_id": nys_snw_category_id}).fetchone()
    session.commit()
    return ClassificationWriteResponse(transaction_id=transaction_id, nys_snw_category_id=nys_snw_category_id,
                                       updated_at=updated[0])


def create_app() -> FastAPI:
    app = FastAPI(title="Teller Reclassification API", version="0.1.0")

    @app.get("/health")
    def health():
        return {"ok": True}

    @app.get("/v1/categories", response_model=List[CategoryOption])
    def list_categories():
        with get_session() as session:
            rows = session.execute(text("""
                SELECT nys_snw_category_id, level_1, level_1_name, level_2, level_2_name, level_3, level_4,
                       categorization, applicability
                  FROM teller.nys_snw_category
                 ORDER BY level_1, level_2, level_3, level_4, categorization, nys_snw_category_id
            """)).mappings().all()
        return [CategoryOption(**row, display_label=_display_label(row)) for row in rows]

    @app.get("/v1/categories/counts", response_model=List[CategoryCountsRow])
    def category_counts():
        with get_session() as session:
            rows = session.execute(text("""
                SELECT c.nys_snw_category_id, c.level_1, c.level_1_name, c.level_2, c.level_2_name, c.level_3, c.level_4,
                       c.categorization, COUNT(tc.transaction_id)::INT AS assigned_transactions
                  FROM teller.nys_snw_category c
             LEFT JOIN teller.transaction_nys_snw_category tc USING (nys_snw_category_id)
              GROUP BY c.nys_snw_category_id, c.level_1, c.level_1_name, c.level_2, c.level_2_name, c.level_3, c.level_4,
                       c.categorization
              ORDER BY assigned_transactions DESC, c.level_1, c.level_2, c.level_3
            """)).mappings().all()
        return [CategoryCountsRow(nys_snw_category_id=row["nys_snw_category_id"], display_label=_display_label(row),
                                  assigned_transactions=row["assigned_transactions"]) for row in rows]

    @app.get("/v1/transactions", response_model=TransactionListResponse)
    def list_transactions(
        search: str = Query(default="", min_length=0, max_length=120),
        status: str = Query(default=""),
        only_unclassified: bool = Query(default=False),
        limit: int = Query(default=150, ge=1, le=500),
        offset: int = Query(default=0, ge=0),
    ):
        filters, params = [], {"limit": limit, "offset": offset}
        if search:
            filters.append("(tt.description ILIKE :search OR tt.transaction_id ILIKE :search)")
            params["search"] = f"%{search}%"
        if status:
            filters.append("tt.status = :status")
            params["status"] = status
        if only_unclassified:
            filters.append("m.nys_snw_category_id IS NULL")
        where_sql = f"WHERE {' AND '.join(filters)}" if filters else ""
        base_query = f"""
            FROM teller.transaction tt
            LEFT JOIN teller.transaction_type ttt USING (transaction_type_id)
            LEFT JOIN teller.transaction_details ttd USING (transaction_details_id)
            LEFT JOIN LATERAL (
                SELECT tnsc.nys_snw_category_id
                  FROM teller.transaction_nys_snw_category tnsc
                 WHERE tnsc.transaction_id = tt.transaction_id
                 ORDER BY tnsc.updated_at DESC
                 LIMIT 1
            ) m ON TRUE
            LEFT JOIN teller.nys_snw_category nsc ON nsc.nys_snw_category_id = m.nys_snw_category_id
            {where_sql}
        """
        with get_session() as session:
            total = session.execute(text(f"SELECT COUNT(*) {base_query}"), params).scalar_one()
            rows = session.execute(text(f"""
                SELECT tt.transaction_id, tt.account_id, tt.date, tt.amount, tt.description, tt.status,
                       ttt.code AS transaction_type_code, ttd.category AS teller_category,
                       m.nys_snw_category_id, nsc.level_1, nsc.level_1_name, nsc.level_2, nsc.level_2_name,
                       nsc.level_3, nsc.level_4, nsc.categorization
                {base_query}
                ORDER BY tt.date DESC, tt.transaction_id DESC
                LIMIT :limit OFFSET :offset
            """), params).mappings().all()
        items = []
        for row in rows:
            classification = None
            if row["nys_snw_category_id"]:
                classification = TransactionCategory(
                    nys_snw_category_id=row["nys_snw_category_id"],
                    display_label=_display_label(row),
                )
            items.append(TransactionRow(transaction_id=row["transaction_id"], account_id=row["account_id"], date=row["date"],
                                        amount=row["amount"], description=row["description"], status=row["status"],
                                        transaction_type_code=row["transaction_type_code"],
                                        teller_category=row["teller_category"], classification=classification))
        return TransactionListResponse(total=total, items=items)

    @app.put("/v1/transactions/{transaction_id}/classification", response_model=ClassificationWriteResponse)
    def set_classification(transaction_id: str, body: ClassificationMutation):
        if body.transaction_id != transaction_id:
            raise HTTPException(status_code=400, detail="Path transaction_id does not match payload transaction_id")
        with get_session() as session:
            return _write_one(session, transaction_id, body.nys_snw_category_id)

    @app.post("/v1/transactions/classifications", response_model=List[ClassificationWriteResponse])
    def set_classifications(body: ClassificationBatchRequest):
        if not body.updates:
            raise HTTPException(status_code=400, detail="updates must not be empty")
        with get_session() as session:
            responses = [_write_one(session, item.transaction_id, item.nys_snw_category_id) for item in body.updates]
        return responses

    return app
