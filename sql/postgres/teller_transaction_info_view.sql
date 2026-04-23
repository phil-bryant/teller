-- #R001: Expose a denormalized transaction reporting view across transaction-related tables.
CREATE OR REPLACE VIEW teller.transaction_info_view 
AS	SELECT 		ta.institution_id, tt.amount, tt.date, tt.description, ttt.code, ttd.category,
       			ttdc.name AS counterparty_name, ttdc.type AS counterparty_type
	FROM 		teller.transaction tt
				LEFT JOIN teller.account ta USING (account_id)
				LEFT JOIN teller.transaction_type ttt USING (transaction_type_id)
				LEFT JOIN teller.transaction_details ttd USING (transaction_details_id)
				LEFT JOIN teller.transaction_details_counterparty ttdc USING (transaction_details_counterparty_id)
				-- #R005: Return rows ordered for stable chronological/reporting consumption.
				ORDER BY tt.date, tt.description
;
