raw_tweets.csv is written by scriptsutomationun_pipeline.ps1 from the Postgres table public.raw_tweets.
Columns, in this order: tweet_id, tweet_created_at, author_username, tweet_text
Until the first export it holds only the header row, and the warehouse loads without tweet text.
