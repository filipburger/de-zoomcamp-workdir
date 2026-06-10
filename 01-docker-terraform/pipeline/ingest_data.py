#!/usr/bin/env python
# coding: utf-8
import pandas as pd
from sqlalchemy import create_engine
from tqdm.auto import tqdm



# vendor id is treated as float, pandas do this automatically due to missing values
# so wee need to specify data types
# and also tell pandas which datetime objects need parsing to avoid string types for dtime
dtype = {
    "VendorID": "Int64",
    "passenger_count": "Int64",
    "trip_distance": "float64",
    "RatecodeID": "Int64",
    "store_and_fwd_flag": "string",
    "PULocationID": "Int64",
    "DOLocationID": "Int64",
    "payment_type": "Int64",
    "fare_amount": "float64",
    "extra": "float64",
    "mta_tax": "float64",
    "tip_amount": "float64",
    "tolls_amount": "float64",
    "improvement_surcharge": "float64",
    "total_amount": "float64",
    "congestion_surcharge": "float64"
}

parse_dates = [
    "tpep_pickup_datetime",
    "tpep_dropoff_datetime"
]


def run():
    """Ingest NYC taxi data into PostgreSQL database."""

pg_user = 'root'
pg_pass = 'root'
pg_host = 'localhost'
pg_port = 5432
pg_db = 'ny_taxi'
year = 2021
month = 1

target_table = 'yellow_taxi_data'
chunksize = 100000

# original data source available at https://www1.nyc.gov/site/tlc/about/tlc-trip-record-data.page)
prefix = 'https://github.com/DataTalksClub/nyc-tlc-data/releases/download/yellow'
url = f'{prefix}/yellow_tripdata_{year}-{month:02d}.csv.gz'
df = pd.read_csv(
    url,
    dtype=dtype,
    parse_dates=parse_dates
)

engine =  create_engine(f'postgresql://{pg_user}:{pg_pass}@{pg_host}:{pg_port}/{pg_db}')

# to sql creates db if not exists and inserts data if available
# head(0) will make sure we just create schema as we want to add
# data in  batches using iterator
df.head(0).to_sql(name=target_table, con=engine, if_exists='replace')
# why not to add all at once it is too big, takes too long and we don;t have any idea about progress
df_iter = pd.read_csv(
    url,
    dtype=dtype,
    parse_dates=parse_dates,
    iterator=True,
    chunksize=chunksize,)

first = True
# use df = next(df), every call of df will iterate next chunk, but it is not very practical
# beter to use for loop
for df_chunk in tqdm(df_iter):
    df_chunk.to_sql(name=target_table, con=engine, if_exists='append')
    first = False

