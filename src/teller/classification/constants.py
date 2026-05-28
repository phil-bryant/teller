from __future__ import annotations

from sqlalchemy import (
    Boolean,
    Column,
    Date,
    DateTime,
    Float,
    Integer,
    MetaData,
    Numeric,
    String,
    Table,
    text,
)
from sqlalchemy.dialects.postgresql import ENUM as PgEnum

_EXISTENCE_QUERIES = {
    ("nys_snw_category", "nys_snw_category_id"): text(
        """
        SELECT 1
          FROM teller.nys_snw_category
         WHERE nys_snw_category_id = :value
         LIMIT 1
    """
    ),
}

_TRANSACTION_COUNT_SQL = text(
    """
    SELECT COUNT(*)
      FROM teller.transaction tt
      LEFT JOIN teller.account ta USING (account_id)
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
      LEFT JOIN LATERAL (
          SELECT ranked.match_id, ranked.state AS match_state,
                 ranked.selected_by AS match_selected_by,
                 ranked.email_message_id, ranked.moved_to_matchy_at,
                 ranked.ai_confidence
            FROM (
                SELECT tem.match_id, tem.state::text AS state, tem.selected_by::text AS selected_by,
                       tem.email_message_id, tem.moved_to_matchy_at, tem.ai_confidence,
                       ROW_NUMBER() OVER (
                           ORDER BY tem.ai_confidence DESC NULLS LAST,
                                    tem.selected_at DESC,
                                    tem.match_id DESC
                       ) AS rn
                  FROM teller.transaction_email_match tem
                 WHERE tem.transaction_id = tt.transaction_id
                   AND tem.active = TRUE
            ) ranked
           WHERE ranked.rn = 1
      ) tem ON TRUE
     WHERE tt.status = 'posted'
       AND (:search = '' OR tt.description ILIKE :search_pattern OR tt.transaction_id ILIKE :search_pattern)
       AND (:status = '' OR tt.status::text = :status)
       AND (:only_unclassified = FALSE OR m.nys_snw_category_id IS NULL)
       AND (:match_state = ''
            OR (:match_state = 'unmatched' AND (tem.match_id IS NULL
                OR (tem.match_state = 'ai_no_match_found' AND tem.match_selected_by <> 'human')))
            OR (:match_state = 'no_email' AND tem.match_state = 'ai_no_match_found' AND tem.match_selected_by = 'human')
            OR (tem.match_state = :match_state))
       AND (:only_unmoved_match = FALSE OR tem.match_id IS NULL OR tem.moved_to_matchy_at IS NULL)
       --R075: Advanced date/institution/amount filters must be enforced at SQL boundary for API parity.
       AND (:start_date IS NULL OR tt.date >= :start_date)
       AND (:end_date IS NULL OR tt.date <= :end_date)
       AND (:institution_id = '' OR ta.institution_id = :institution_id)
       AND (:min_amount IS NULL OR tt.amount >= :min_amount)
       AND (:max_amount IS NULL OR tt.amount <= :max_amount)
"""
)

_TRANSACTION_LIST_SQL = text(
    """
    SELECT tt.transaction_id, tt.account_id, ta.institution_id, ta.last_four AS account_last_four,
           tt.date, tt.amount, tt.description, tt.status,
           ttt.code AS transaction_type_code, ttd.category AS teller_category,
           m.nys_snw_category_id, nsc.level_1, nsc.level_1_name, nsc.level_2, nsc.level_2_name,
           nsc.level_3, nsc.level_4, nsc.categorization,
           tem.match_id, tem.match_state, tem.match_selected_by,
           tem.match_email_message_id, tem.moved_to_matchy_at,
           tem.match_ai_confidence, tem.match_count
      FROM teller.transaction tt
      LEFT JOIN teller.account ta USING (account_id)
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
      LEFT JOIN LATERAL (
          SELECT ranked.match_id, ranked.state AS match_state,
                 ranked.selected_by AS match_selected_by,
                 ranked.email_message_id AS match_email_message_id,
                 ranked.moved_to_matchy_at, ranked.ai_confidence AS match_ai_confidence,
                 ranked.match_count
            FROM (
                SELECT tem.match_id, tem.state::text AS state, tem.selected_by::text AS selected_by,
                       tem.email_message_id, tem.moved_to_matchy_at, tem.ai_confidence,
                       COUNT(*) OVER ()::INT AS match_count,
                       ROW_NUMBER() OVER (
                           ORDER BY tem.ai_confidence DESC NULLS LAST,
                                    tem.selected_at DESC,
                                    tem.match_id DESC
                       ) AS rn
                  FROM teller.transaction_email_match tem
                 WHERE tem.transaction_id = tt.transaction_id
                   AND tem.active = TRUE
            ) ranked
           WHERE ranked.rn = 1
      ) tem ON TRUE
     WHERE tt.status = 'posted'
       AND (:search = '' OR tt.description ILIKE :search_pattern OR tt.transaction_id ILIKE :search_pattern)
       AND (:status = '' OR tt.status::text = :status)
       AND (:only_unclassified = FALSE OR m.nys_snw_category_id IS NULL)
       AND (:match_state = ''
            OR (:match_state = 'unmatched' AND (tem.match_id IS NULL
                OR (tem.match_state = 'ai_no_match_found' AND tem.match_selected_by <> 'human')))
            OR (:match_state = 'no_email' AND tem.match_state = 'ai_no_match_found' AND tem.match_selected_by = 'human')
            OR (tem.match_state = :match_state))
       AND (:only_unmoved_match = FALSE OR tem.match_id IS NULL OR tem.moved_to_matchy_at IS NULL)
       --R075: Advanced date/institution/amount filters must be enforced at SQL boundary for API parity.
       AND (:start_date IS NULL OR tt.date >= :start_date)
       AND (:end_date IS NULL OR tt.date <= :end_date)
       AND (:institution_id = '' OR ta.institution_id = :institution_id)
       AND (:min_amount IS NULL OR tt.amount >= :min_amount)
       AND (:max_amount IS NULL OR tt.amount <= :max_amount)
    ORDER BY tt.date DESC, tt.transaction_id DESC
    LIMIT :limit OFFSET :offset
"""
)

_WRITE_TOKEN_PSA_ITEM = "TELLER_CLASSIFIER_WRITE_TOKEN"
_WRITE_TOKEN_HEADER = "x-teller-write-token"

_CATEGORY_TEXT_FIELDS = (
    "level_1",
    "level_1_name",
    "level_2",
    "level_2_name",
    "level_3",
    "level_4",
    "categorization",
    "applicability",
)
_CATEGORY_SCHEMA_PROPERTIES = {
    field_name: {
        "type": "string",
        "minLength": 1,
        "maxLength": 120,
        "pattern": r"^[\x20-\x7E]*[\x21-\x7E][\x20-\x7E]*$",
    }
    for field_name in _CATEGORY_TEXT_FIELDS
}
_CATEGORY_SCHEMA_REQUIRE_ONE = [{"required": [field_name]} for field_name in _CATEGORY_TEXT_FIELDS]

_MATCH_STATE_ENUM = PgEnum(
    "ai_no_match_found",
    "ai_candidate_uncertain",
    "ai_match_confident",
    "human_confirmed_ai_match",
    "human_overrode_ai_match",
    name="transaction_email_match_state",
    schema="teller",
    create_type=False,
)
_MATCH_SELECTED_BY_ENUM = PgEnum(
    "ai",
    "human",
    name="transaction_email_match_selected_by",
    schema="teller",
    create_type=False,
)
_SQL_METADATA = MetaData()
_MATCH_REVIEW_TABLE = Table(
    "transaction_email_match",
    _SQL_METADATA,
    Column("match_id", Integer),
    Column("transaction_id", String),
    Column("email_message_id", String),
    Column("state", _MATCH_STATE_ENUM),
    Column("ai_confidence", Float),
    Column("selected_by", _MATCH_SELECTED_BY_ENUM),
    Column("selected_at", DateTime(timezone=True)),
    Column("updated_at", DateTime(timezone=True)),
    Column("moved_to_matchy_at", DateTime(timezone=True)),
    Column("active", Boolean),
    schema="teller",
)
_TRANSACTION_TABLE = Table(
    "transaction",
    _SQL_METADATA,
    Column("transaction_id", String),
    Column("description", String),
    Column("amount", Numeric),
    Column("date", Date),
    schema="teller",
)

_LATEST_MATCH_RUN_SQL = text(
    """
    SELECT match_run_id
      FROM teller.transaction_email_match_run
     WHERE transaction_id = :transaction_id
     ORDER BY started_at DESC, match_run_id DESC
     LIMIT 1
"""
)

_LATEST_RUN_CANDIDATES_SQL = text(
    """
    SELECT candidate_id,
           email_message_id,
           score,
           reason_json,
           email_received_at,
           is_selected_by_ai,
           is_unmatched_email_priority,
           cached_subject,
           cached_sender,
           cached_snippet,
           cached_fetched_at
      FROM teller.transaction_email_candidate
     WHERE match_run_id = :match_run_id
     ORDER BY score DESC, email_received_at DESC NULLS LAST, candidate_id ASC
"""
)

_ACTIVE_MATCH_EMAILS_SQL = text(
    """
    SELECT email_message_id,
           state::text AS state,
           selected_by::text AS selected_by
      FROM teller.transaction_email_match
     WHERE transaction_id = :transaction_id
       AND active = TRUE
       AND email_message_id IS NOT NULL
     ORDER BY selected_at DESC, match_id DESC
"""
)

_UPDATE_CANDIDATE_CACHE_SQL = text(
    """
    UPDATE teller.transaction_email_candidate
       SET cached_subject = :cached_subject,
           cached_sender = :cached_sender,
           cached_snippet = :cached_snippet,
           cached_fetched_at = CURRENT_TIMESTAMP,
           updated_at = CURRENT_TIMESTAMP
     WHERE candidate_id = :candidate_id
"""
)

_EMAIL_MESSAGE_ID_PATTERN = r"^[A-Za-z0-9_\-=]+$"
_EMAIL_MESSAGE_ID_MAX_LENGTH = 4096
#R062: Structured search fields are optional, so empty strings must validate.
_EMAIL_SEARCH_QUERY_PATTERN = r"^[\x20-\x7E]*$"

_MAILCART_ENRICHMENT_WORKERS = 16
