-- Postgres -> datasets\raw_tweets\raw_tweets.csv
-- Columns must stay in the order of bronze.twitter_raw_tweets:
--   tweet_id, tweet_created_at, author_username, tweet_text
COPY (
    SELECT
        tweet_id,
        to_char(created_at::timestamptz AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS') AS tweet_created_at,
        username                                                                    AS author_username,
        translate(tweet_text, chr(10) || chr(13) || chr(9), '   ')                  AS tweet_text
    FROM public.raw_tweets
    ORDER BY created_at
) TO STDOUT WITH (FORMAT csv, HEADER true);
