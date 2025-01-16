WITH first_month_appearances AS (
    SELECT 
        cp.id,
        cp.name,
        MIN(DATE_TRUNC('month', t.date)) as first_month
    FROM teller.transaction_counterparties cp
    JOIN teller.transactions t ON t.counterparty_id = cp.id
    GROUP BY cp.id, cp.name
    HAVING MIN(DATE_TRUNC('month', t.date)) >= '2024-01-01'
),
first_month_totals AS (
    SELECT 
        fma.id,
        fma.name,
        fma.first_month,
        SUM(
            CASE 
                WHEN a.subtype = 'credit_card' THEN -t.amount
                ELSE t.amount
            END
        ) as net_total
    FROM first_month_appearances fma
    JOIN teller.transactions t ON t.counterparty_id = fma.id
    JOIN teller.accounts a ON t.account_id = a.id
    WHERE DATE_TRUNC('month', t.date) = fma.first_month
    GROUP BY fma.id, fma.name, fma.first_month
)
SELECT 
    TO_CHAR(first_month, 'YYYY-MM') as month,
    name as counterparty_name,
    net_total
FROM first_month_totals
ORDER BY 
    first_month ASC,
    net_total ASC; 