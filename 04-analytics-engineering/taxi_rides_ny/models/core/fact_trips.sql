{{ config(materialized='table') }}

with
    green_tripdata as (
        select *, 'Green' as service_type from {{ ref('stg_green_tripdata') }}
    ),
    yellow_tripdata as (
        select *, 'Yellow' as service_type from {{ ref('stg_yellow_tripdata') }}
    ),
    trips_unioned as (
        select *
        from green_tripdata
        union all
        select *
        from yellow_tripdata
    ),
    dim_zones as (select * from {{ ref('dim_zones') }} where borough != 'Unknown')

select
    t.trip_id,
    t.vendor_id,
    t.rate_code_id,
    t.pickup_location_id,
    t.dropoff_location_id,
    t.pickup_datetime,
    t.dropoff_datetime,
    t.store_and_fwd_flag,
    t.passenger_count,
    t.trip_distance,
    t.fare_amount,
    t.extra,
    t.mta_tax,
    t.tip_amount,
    t.tolls_amount,
    t.ehail_fee,
    t.improvement_surcharge,
    t.total_amount,
    t.payment_type,
    t.payment_type_description,
    pickup_zone.borough as pickup_borough,
    pickup_zone.zone as pickup_zone,
    dropoff_zone.borough as dropoff_borough,
    dropoff_zone.zone as dropoff_zone
from trips_unioned t
inner join dim_zones as pickup_zone on t.pickup_location_id = pickup_zone.locationid
inner join dim_zones as dropoff_zone on t.dropoff_location_id = dropoff_zone.locationid
