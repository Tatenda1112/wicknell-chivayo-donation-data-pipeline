-- Postgres -> datasets\llm_extract\llm_donations_extract.csv
-- Columns must stay in the order of bronze.llm_donations_extract.
-- Line breaks and tabs inside text are replaced by spaces so every row is one line.
COPY (
    SELECT
        donation_id,
        tweet_id,
        translate(donor_name,           chr(10) || chr(13) || chr(9), '   ') AS donor_name,
        translate(recipient_name,       chr(10) || chr(13) || chr(9), '   ') AS recipient_name,
        translate(donation_description, chr(10) || chr(13) || chr(9), '   ') AS donation_description,
        amount_original,
        currency,
        amount_usd,
        donation_date::date             AS donation_date,
        translate(country,              chr(10) || chr(13) || chr(9), '   ') AS country,
        translate(location,             chr(10) || chr(13) || chr(9), '   ') AS location,
        translate(donation_theme,       chr(10) || chr(13) || chr(9), '   ') AS donation_theme,
        confidence_score,
        translate(ai_explanation,       chr(10) || chr(13) || chr(9), '   ') AS ai_explanation,
        extracted_at,
        donation_key,
        recipient_type,
        donation_type,
        translate(item_name,            chr(10) || chr(13) || chr(9), '   ') AS item_name,
        quantity,
        amount_per_recipient,
        translate(purpose,              chr(10) || chr(13) || chr(9), '   ') AS purpose,
        commitment_status,
        translate(source_excerpt,       chr(10) || chr(13) || chr(9), '   ') AS source_excerpt,
        translate(beneficiary_names::text, chr(10) || chr(13) || chr(9), '   ') AS beneficiary_names,
        allocation_scope
    FROM public.donations
    ORDER BY donation_id
) TO STDOUT WITH (FORMAT csv, HEADER true);
