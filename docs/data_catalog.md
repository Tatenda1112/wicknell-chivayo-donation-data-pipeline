# Data catalog

What each layer holds and what the Gold views expose to Power BI.

## Bronze (raw, text only)

One table per source file. Every column is `NVARCHAR`, so nothing is changed or rejected at load.

| Table | Source file | Content |
|---|---|---|
| `bronze.twitter_raw_tweets` | `datasets/raw_tweets/raw_tweets.csv` | Tweets collected by n8n |
| `bronze.llm_donations_extract` | `datasets/llm_extract/llm_donations_extract.csv` | One row per gift, as extracted by the LLM |
| `bronze.reviewed_money` | `datasets/curated/money.csv` | Reviewed cash gifts |
| `bronze.reviewed_vehicle` | `datasets/curated/vehicle.csv` | Reviewed vehicle gifts |
| `bronze.reviewed_house` | `datasets/curated/house.csv` | Reviewed house gifts |
| `bronze.reviewed_other_giving` | `datasets/curated/other_giving.csv` | Reviewed gifts of any other kind |
| `bronze.reviewed_excluded` | `datasets/curated/excluded_not_donations.csv` | Rows judged not to be donations, with the reason |
| `bronze.reviewed_corrections_log` | `datasets/curated/corrections_log.csv` | Every change made to the LLM output |
| `bronze.reviewed_baseline` | `datasets/curated/reviewed_baseline_ids.csv` | Ids of the donations already reviewed by hand |
| `bronze.load_log` | (written by the loader) | One row per file per load: rows, duration, status, error |

Rows added by the automatic sorting rules carry `origin = 'auto_rule'` and `review_flag = 'auto_unreviewed'`.

## Silver (clean, typed, enriched)

| Table | Grain | Notes |
|---|---|---|
| `silver.donation_money` | one cash gift | amounts typed, ZAR converted to USD, `counts_toward_total` |
| `silver.donation_vehicle` | one vehicle gift line | vehicle class, quantity, unit and total value |
| `silver.donation_house` | one house gift line | house count, value, nature of the gift |
| `silver.donation_other` | one other gift line | category, quantity, value |
| `silver.recipient` | one recipient | one standard spelling per recipient, `recipient_group` |
| `silver.tweet` | one tweet | text, date, number of donation lines |
| `silver.exchange_rate` | one currency | rate to USD and where it came from |
| `silver.excluded` | one excluded row | reason it is not a donation |
| `silver.data_quality_issues` | one issue | review flags, LLM corrections, duplicates, overlaps |

Columns added in Silver: `donation_year`, `donation_month`, `days_tweet_to_donation`,
`status_group`, `is_pledge`, `is_delivered`, `recipient_group`, `usd_is_converted`,
`counts_toward_total`, `not_counted_reason`.

### What is kept out of the totals

A row stays in its table but gets `counts_toward_total = 0` when it is:

| Reason starts with | Meaning |
|---|---|
| `Declined:` | the commitment was declined or rejected |
| `Duplicate:` | the tweet text shows it is the same gift as another row |
| `Not a donation:` | loan, expense, fee for a service, personal purchase |
| `Family:` | personal gift to the donor's wife or ex-wife |

## Gold (views for Power BI)

Star schema: one fact view and five dimensions, plus ready-made aggregates.

| View | Columns |
|---|---|
| `gold.fact_donations` | `donation_line_id`, `donation_type_key`, `source_donation_id`, `tweet_id`, `date_key`, `recipient_key`, `status_key`, `item_key`, `item_name`, `quantity`, `currency_original`, `amount_original`, `cash_amount_usd`, `asset_value_usd`, `usd_is_converted`, `counts_toward_total`, `not_counted_reason`, `overlap_group`, `review_flag` |
| `gold.dim_date` | `date_key`, `full_date`, `year`, `quarter`, `month_number`, `month_name`, `year_month`, `day_of_month`, `day_name` |
| `gold.dim_recipient` | `recipient_key`, `recipient_name`, `recipient_type`, `recipient_group` |
| `gold.dim_donation_type` | `donation_type_key`, `donation_type`, `description` |
| `gold.dim_status` | `status_key`, `commitment_status`, `status_group` |
| `gold.dim_item` | `item_key`, `donation_type_key`, `item_category` |
| `gold.fact_donations_flat` | the fact joined to every dimension, one wide row per donation line |
| `gold.agg_donations_by_month` | `year_month`, `year`, `month_number`, `status_group`, `donation_lines`, `cash_usd`, `asset_value_usd`, `vehicles`, `houses` |
| `gold.agg_donations_by_type` | `donation_type`, `status_group`, `donation_lines`, `recipients`, `cash_usd`, `asset_value_usd`, `units` |
| `gold.agg_donations_by_recipient_group` | `recipient_group`, `status_group`, `donation_lines`, `recipients`, `cash_usd`, `asset_value_usd` |
| `gold.agg_donations_by_recipient` | `recipient_name`, `recipient_type`, `recipient_group`, `donation_lines`, `cash_usd`, `asset_value_usd`, `vehicles` |
| `gold.agg_promised_vs_delivered` | `status_group`, `donation_lines`, `cash_usd`, `asset_value_usd`, `vehicles`, `houses` |

The aggregate views only include rows with `counts_toward_total = 1`.
`cash_amount_usd` is money; `asset_value_usd` is the stated value of vehicles, houses and other items.
