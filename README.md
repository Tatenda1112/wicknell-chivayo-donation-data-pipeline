# Wicknell Chivayo Donation Data Pipeline

An end-to-end data engineering and analytics project that collects, processes, cleans and analyzes public donation announcements posted on X by the late Wicknell Chivayo.

The project processes **1,102 tweets** and transforms them into traceable data for analysis in Power BI. It uses a Medallion Architecture with Bronze, Silver and Gold layers.

> **Disclaimer:** This is a learning project. It is not affiliated with or endorsed by any person or organization. The figures reflect public announcements and are not independently verified audit results.

## Project Goals

- Automate the collection of public posts from X.
- Extract donation details from tweet text using Claude AI.
- Store and organize data in PostgreSQL and SQL Server.
- Clean and check records through Bronze, Silver and Gold data layers.
- Build Power BI dashboards that link results back to their source tweets.

## Project Results

| Measure | Result |
|---|---:|
| Announced cash donations | $43 million |
| Cash classified as delivered | $13 million |
| Cash classified as promised | $30 million |
| Vehicles | 793 |
| Estimated vehicle value | About $28 million |
| Houses | 10 |
| Recipients | 267 |

### Top Recipients by Announced Cash

| Recipient | Announced amount |
|---|---:|
| ZIFA | $10.0 million |
| Bishop Nehemiah Mutendi | $8.9 million |
| Zion Christian Church | $4.4 million |

Sports groups received about **$15 million** in announced cash, while religious groups received about **$13 million**.

### Understanding “Delivered” and “Promised”

Some gifts were announced before delivery was later confirmed, sometimes on Facebook. Because this project uses posts from X, delivery status is classified based on the wording of those posts. These labels are not independent confirmation that a donation was delivered.

## Data Pipeline

1. **Collect:** An n8n workflow runs daily at 9:00 AM and retrieves new posts through TwitterAPI.io.
2. **Store raw posts:** Tweets are saved in PostgreSQL. Unique tweet IDs help prevent duplicates.
3. **Extract information:** Claude AI identifies whether a post describes a donation and extracts fields such as recipient, donation type, quantity, amount, currency, purpose and date.
4. **Load into SQL Server:** The extracted data is organized into Bronze, Silver and Gold layers.
5. **Analyze:** Gold views provide structured data for Power BI dashboards. Records can be traced back to their original tweets.

## Data Architecture

### Bronze

Contains **8 raw tables** that preserve source and extracted data for further processing.

### Silver

Contains **9 cleaned tables** and a data quality log. This layer supports corrections, overlap checks and the review of records that could distort the analysis.

### Gold

Contains star schema views designed for reporting and analysis in Power BI.

## Data Quality

- **1,102 tweets** were collected and processed.
- **435 donation lines** were counted in the analysis.
- **22 rows** were not counted in the final totals.
- **59 rows** were corrected during LLM-assisted review.
- **10 entries** were excluded, including posts where Chivayo was not the donor and aggregate claims that could double count vehicles.
- Dashboard records link back to their original tweets to support traceability.

## Tools and Technologies

- **n8n** — workflow automation
- **TwitterAPI.io** — post retrieval
- **Claude AI** — donation classification and information extraction
- **PostgreSQL** — raw tweet storage
- **SQL Server** — data warehouse and transformations
- **Power BI** — dashboards and reporting

## Repository Structure

```text
.
├── data/
├── sql_scripts/
│   ├── bronze/
│   ├── silver/
│   └── gold/
├── powerbi/
└── README.md
```

## Limitations

- The analysis is based on public posts from X and may not include announcements made only on other platforms.
- “Promised” and “delivered” classifications are based on post wording, not independent verification.
- Some amounts and asset valuations may be estimates or reflect information stated in the source posts.
- AI-assisted extraction can make mistakes. The project includes data quality checks and source links, but results should be interpreted with these limitations in mind.
