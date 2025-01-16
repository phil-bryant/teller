WITH checking_examples AS (
    SELECT 
        a.id as account_id,
        a.name as account_name,
        a.type as account_type,
        a.subtype as account_subtype,
        t.date,
        cp.name as counterparty,
        t.amount,
        t.description
    FROM teller.accounts a
    JOIN teller.transactions t ON t.account_id = a.id
    LEFT JOIN teller.transaction_counterparties cp ON cp.id = t.counterparty_id
    WHERE a.subtype = 'checking'
    ORDER BY t.date DESC
    LIMIT 5
),
credit_examples AS (
    SELECT 
        a.id as account_id,
        a.name as account_name,
        a.type as account_type,
        a.subtype as account_subtype,
        t.date,
        cp.name as counterparty,
        t.amount,
        t.description
    FROM teller.accounts a
    JOIN teller.transactions t ON t.account_id = a.id
    LEFT JOIN teller.transaction_counterparties cp ON cp.id = t.counterparty_id
    WHERE a.subtype = 'credit_card'
    ORDER BY t.date DESC
    LIMIT 5
)
SELECT * FROM checking_examples
UNION ALL
SELECT * FROM credit_examples
ORDER BY account_subtype, date DESC;