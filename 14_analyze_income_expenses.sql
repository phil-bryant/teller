WITH income_expenses AS (
    SELECT
        date_trunc('month', date) AS month,
        CASE 
            WHEN amount >= 0 THEN 'income'
            ELSE 'expense'
        END AS type,
        SUM(amount) AS total_amount,
        COUNT(*) AS transaction_count
    FROM teller.transactions
    WHERE 
        date >= '2024-01-01' 
        AND date < '2025-01-01'
        AND status = 'posted'
    GROUP BY 
        date_trunc('month', date),
        CASE 
            WHEN amount >= 0 THEN 'income'
            ELSE 'expense'
        END
)
SELECT 
    to_char(month, 'YYYY_MM') AS month,
    COALESCE(MAX(CASE WHEN type = 'income' THEN total_amount END), 0) AS income,
    COALESCE(ABS(MIN(CASE WHEN type = 'expense' THEN total_amount END)), 0) AS expenses,
    COALESCE(MAX(CASE WHEN type = 'income' THEN total_amount END), 0) + 
    COALESCE(MIN(CASE WHEN type = 'expense' THEN total_amount END), 0) AS net_cashflow,
    COALESCE(MAX(CASE WHEN type = 'income' THEN transaction_count END), 0) AS income_transactions,
    COALESCE(MAX(CASE WHEN type = 'expense' THEN transaction_count END), 0) AS expense_transactions
FROM income_expenses
GROUP BY month
ORDER BY month;

-- Category breakdown for expenses
SELECT 
    category,
    COUNT(*) as transaction_count,
    ABS(SUM(amount)) as total_spent,
    ROUND(ABS(AVG(amount)), 2) as avg_transaction_amount,
    ROUND(ABS(SUM(amount)) / SUM(ABS(SUM(amount))) OVER () * 100, 2) as percentage_of_total
FROM teller.transactions
WHERE 
    date >= '2024-01-01' 
    AND date < '2025-01-01'
    AND status = 'posted'
    AND amount < 0
    AND category IS NOT NULL
GROUP BY category
ORDER BY total_spent DESC;

-- Top merchants by expense
SELECT 
    tc.name as merchant_name,
    COUNT(*) as transaction_count,
    ABS(SUM(t.amount)) as total_spent,
    ROUND(ABS(AVG(t.amount)), 2) as avg_transaction_amount
FROM teller.transactions t
JOIN teller.transaction_counterparties tc ON t.counterparty_id = tc.id
WHERE 
    t.date >= '2024-01-01' 
    AND t.date < '2025-01-01'
    AND t.status = 'posted'
    AND t.amount < 0
GROUP BY tc.name
ORDER BY total_spent DESC
LIMIT 10;