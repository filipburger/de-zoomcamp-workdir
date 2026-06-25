-- ============================================================
-- BigQuery ML — Tip Amount Prediction (Linear Regression)
-- Module 3: Data Warehouse — ML Section
-- ============================================================
-- Goal: predict tip_amount for NYC yellow taxi trips
-- Algorithm: Linear Regression (continuous value prediction)
-- All ML happens inside BigQuery — no Python, no external tools
-- ============================================================
-- ============================================================
-- 1. FEATURE EXPLORATION — SELECT CANDIDATE FEATURES
-- ============================================================
-- First step before any ML: understand what data you're working with
-- Selected features and why:
--   passenger_count   → might influence tipping behavior
--   trip_distance     → longer trips typically = higher tips (absolute)
--   PULocationID      → pickup zone affects tipping culture (airport vs street)
--   DOLocationID      → dropoff zone similarly relevant
--   payment_type      → cash trips rarely report tips (driver keeps cash tips)
--                       credit card tips are captured → important bias to know
--   fare_amount       → base fare correlates with tip (% tipping behavior)
--   tolls_amount      → part of total trip cost
--   tip_amount        → TARGET variable — what we're predicting
--
-- WHERE fare_amount != 0: removes cancelled/zero-fare trips
-- these are data quality issues, not real trips — would mislead the model
SELECT
    passenger_count,
    trip_distance,
    pulocationid,
    dolocationid,
    payment_type,
    fare_amount,
    tolls_amount,
    tip_amount
FROM
    `taxi-rides-ny.nytaxi.yellow_tripdata_partitioned`
WHERE
    fare_amount != 0;

-- ============================================================
-- 2. CREATE ML-READY TABLE WITH EXPLICIT TYPES
-- ============================================================
-- Why create a separate ML table instead of using the partitioned table directly?
-- → explicit type casting ensures BigQuery ML interprets features correctly
-- → PULocationID, DOLocationID, payment_type cast to STRING:
--   these are CATEGORICAL (location IDs, payment codes) not numerical
--   if left as INTEGER, model treats 132 > 131 as meaningful — it's not
--   as STRING, BigQuery ML will auto one-hot encode them (binary columns per category)
--   this is the categorical encoding concept we discussed — making math possible
-- → cleaner, smaller table with only the columns ML needs (no irrelevant columns)
-- → separates raw analytical table from ML feature table (good practice)
--
-- Type decisions explained:
--   passenger_count  INTEGER  → truly numerical, 1-6 passengers has real order
--   trip_distance    FLOAT64  → continuous numerical, meaningful magnitude
--   PULocationID     STRING   → categorical, 265 zones, no inherent ordering
--   DOLocationID     STRING   → same as above
--   payment_type     STRING   → categorical (1=credit, 2=cash etc.) — no ordering
--   fare_amount      FLOAT64  → continuous, will be standardized automatically
--   tolls_amount     FLOAT64  → continuous
--   tip_amount       FLOAT64  → TARGET variable, continuous — predicting this
CREATE OR REPLACE TABLE `taxi-rides-ny.nytaxi.yellow_tripdata_ml` (
    `passenger_count` integer,
    `trip_distance` FLOAT64,
    `PULocationID` string,
    `DOLocationID` string,
    `payment_type` string,
    `fare_amount` FLOAT64,
    `tolls_amount` FLOAT64,
    `tip_amount` FLOAT64
) AS (
    SELECT
        passenger_count,
        trip_distance,
        CAST(pulocationid AS string),
        CAST(dolocationid AS string),
        CAST(payment_type AS string),
        fare_amount,
        tolls_amount,
        tip_amount
    FROM
        `taxi-rides-ny.nytaxi.yellow_tripdata_partitioned`
    WHERE
        fare_amount != 0
);

-- ============================================================
-- 3. TRAIN THE MODEL
-- ============================================================
-- BigQuery ML handles the entire training pipeline:
-- → automatic feature preprocessing (standardization of numerics,
--   one-hot encoding of STRING columns — exactly what we discussed)
-- → train/eval split via DATA_SPLIT_METHOD='AUTO_SPLIT'
-- → gradient descent optimization
-- → stores trained model as a BQ object (queryable like a table)
--
-- OPTIONS explained:
--   model_type='linear_reg'      → linear regression for continuous target
--                                  appropriate since tip_amount is continuous $
--   input_label_cols=['tip_amount'] → the TARGET column (what we predict)
--                                     everything else becomes a feature automatically
--   DATA_SPLIT_METHOD='AUTO_SPLIT'  → BQ automatically splits data into
--                                     training set (~80%) and evaluation set (~20%)
--                                     prevents evaluating on data the model trained on
--                                     (overfitting detection)
--
-- WHERE tip_amount IS NOT NULL:
-- → removes rows where tip wasn't recorded (mostly cash trips)
-- → cash tips are NOT captured in the data — passenger paid cash tip directly
-- → including NULLs would mislead model (NULL ≠ zero tip, it's missing data)
-- → important data quality decision: this model effectively predicts
--   credit card tip behavior, not all tip behavior
CREATE
OR replace model `taxi-rides-ny.nytaxi.tip_model` OPTIONS(
    model_type = 'linear_reg',
    input_label_cols = ['tip_amount'],
    data_split_method = 'AUTO_SPLIT'
) AS
SELECT
    *
FROM
    `taxi-rides-ny.nytaxi.yellow_tripdata_ml`
WHERE
    tip_amount IS NOT NULL;

-- ============================================================
-- 4. INSPECT FEATURES
-- ============================================================
-- ML.FEATURE_INFO shows what preprocessing BigQuery ML applied automatically:
-- → which columns were standardized (numerical → mean=0, std=1)
-- → which columns were one-hot encoded (STRING categories → binary columns)
-- → category counts, null counts, min/max/mean/std per feature
-- → useful to verify BQ interpreted your features as intended
--   e.g. confirm PULocationID was treated as categorical not numerical
--
-- This is where you'd catch mistakes like forgetting to CAST an ID column
-- to STRING — if BQ shows it as NUMERIC it was treated as a continuous value
SELECT
    *
FROM
    ml.feature_info (model `taxi-rides-ny.nytaxi.tip_model`);

-- ============================================================
-- 5. EVALUATE THE MODEL
-- ============================================================
-- ML.EVALUATE runs the model against the evaluation split and returns metrics
-- For linear regression, key metrics to check:
--
--   mean_absolute_error (MAE)
--   → average prediction error in original units ($)
--   → MAE=$1.50 means predictions are off by $1.50 on average
--   → most interpretable metric for business stakeholders
--
--   mean_squared_error (MSE)
--   → penalizes large errors more than MAE (errors are squared)
--   → sensitive to outliers — a $50 error counts 2500x a $1 error
--
--   root_mean_squared_error (RMSE)
--   → square root of MSE, back in original $ units
--   → more comparable to MAE but still outlier-sensitive
--
--   r2_score (R²)
--   → 0 to 1, how much variance in tip_amount the model explains
--   → R²=0.85 means model explains 85% of tip variation
--   → R²=1.0 = perfect, R²=0 = no better than predicting the mean every time
--
--   explained_variance
--   → similar to R², measures model's explanatory power
--
-- Note: passing the same dataset used for training would give overly
-- optimistic metrics — AUTO_SPLIT already held out an eval set,
-- so this is evaluating on genuinely unseen data
SELECT
    *
FROM
    ml.evaluate (
        model `taxi-rides-ny.nytaxi.tip_model`,
        (
            SELECT
                *
            FROM
                `taxi-rides-ny.nytaxi.yellow_tripdata_ml`
            WHERE
                tip_amount IS NOT NULL
        )
    );

-- ============================================================
-- 6. PREDICT
-- ============================================================
-- ML.PREDICT runs inference on new data and returns:
-- → predicted_tip_amount: the model's tip prediction for each row
-- → all original columns from the input table
-- → useful for: scoring new trips, batch predictions, downstream analysis
--
-- In production this would receive NEW trips without known tip_amount
-- Here we're predicting on known data (tip_amount exists) to compare
-- predicted vs actual — manual evaluation beyond ML.EVALUATE metrics
--
-- Remember: back-transformation from standardized scale to $ happens
-- automatically — predicted_tip_amount is in original dollar units
SELECT
    *
FROM
    ml.predict (
        model `taxi-rides-ny.nytaxi.tip_model`,
        (
            SELECT
                *
            FROM
                `taxi-rides-ny.nytaxi.yellow_tripdata_ml`
            WHERE
                tip_amount IS NOT NULL
        )
    );

-- ============================================================
-- 7. EXPLAIN PREDICTIONS (Explainable AI)
-- ============================================================
-- ML.EXPLAIN_PREDICT adds feature attribution to each prediction:
-- → tells you WHY the model predicted a specific value for each row
-- → uses Shapley values (SHAP) — game theory-based attribution method
-- → each feature gets a contribution score showing how much it pushed
--   the prediction up or down from the baseline
--
-- STRUCT(3 as top_k_features):
-- → only return the top 3 most influential features per prediction
-- → reduces output size (otherwise one row per feature per prediction)
-- → useful for: explaining individual predictions to stakeholders,
--   debugging unexpected predictions, identifying dominant features
--
-- Example output interpretation:
-- predicted_tip=$3.50, baseline=$2.00
-- → trip_distance: +$1.20 (long trip pushed tip up)
-- → payment_type_1: +$0.80 (credit card trips tip more)
-- → PULocationID_132: -$0.50 (airport pickup reduces tip % behavior)
--
-- This is why explainability matters for DE/analytics:
-- a model that predicts correctly but can't explain why is hard to trust
-- and debug when it eventually makes wrong predictions
SELECT
    *
FROM
    ml.explain_predict (
        model `taxi-rides-ny.nytaxi.tip_model`,
        (
            SELECT
                *
            FROM
                `taxi-rides-ny.nytaxi.yellow_tripdata_ml`
            WHERE
                tip_amount IS NOT NULL
        ),
        STRUCT(3 AS top_k_features)
    );

-- ============================================================
-- 8. HYPERPARAMETER TUNING
-- ============================================================
-- Default model uses fixed hyperparameters — may not be optimal
-- Hyperparameter tuning systematically searches for better settings
--
-- What are hyperparameters?
-- → parameters that control HOW the model trains, not WHAT it learns
-- → not learned from data — you set them before training
-- → example: learning rate, regularization strength, tree depth
--
-- OPTIONS explained:
--   num_trials=5          → try 5 different hyperparameter combinations
--   max_parallel_trials=2 → run 2 trials simultaneously (faster, costs more)
--
--   l1_reg (Lasso regularization):
--   → penalizes model for having large coefficients
--   → hparam_range(0, 20) → try values between 0 and 20
--   → l1 specifically: drives some coefficients to exactly zero
--     (automatic feature selection — unimportant features get zeroed out)
--   → higher l1 = simpler model, less overfitting, potentially less accuracy
--
--   l2_reg (Ridge regularization):
--   → also penalizes large coefficients but differently than l1
--   → hparam_candidates([0, 0.1, 1, 10]) → try only these 4 specific values
--   → l2: shrinks coefficients toward zero but rarely to exactly zero
--     (keeps all features but reduces their influence)
--   → higher l2 = smoother model, handles correlated features better
--
-- Why regularization matters here:
-- → we have high-cardinality one-hot encoded columns (265 locations × 2)
-- → that's 530 binary columns just for locations — many won't matter
-- → without regularization the model might overfit to irrelevant location codes
-- → l1 regularization will zero out unimportant location coefficients automatically
--
-- l1 vs l2 rule of thumb:
--   many irrelevant features → l1 (zeroes them out, simpler model)
--   correlated features      → l2 (handles multicollinearity better)
--   both                     → ElasticNet (combines l1 + l2, not shown here)
--
-- BQ will train 5 models with different l1/l2 combinations and
-- return the best performing one based on evaluation metrics
CREATE
OR replace model `taxi-rides-ny.nytaxi.tip_hyperparam_model` OPTIONS(
    model_type = 'linear_reg',
    input_label_cols = ['tip_amount'],
    data_split_method = 'AUTO_SPLIT',
    num_trials = 5,
    max_parallel_trials = 2,
    l1_reg = hparam_range (0, 20),
    l2_reg = hparam_candidates ([0, 0.1, 1, 10])
) AS
SELECT
    *
FROM
    `taxi-rides-ny.nytaxi.yellow_tripdata_ml`
WHERE
    tip_amount IS NOT NULL;

-- ============================================================
-- SUMMARY: BIGQUERY ML WORKFLOW
-- ============================================================
--
-- 1. Explore raw data        → SELECT candidate features, understand distributions
-- 2. Build feature table     → explicit types, CAST categoricals to STRING,
--                              filter bad data (fare=0, tip IS NULL)
-- 3. Train model             → CREATE MODEL, BQ handles preprocessing automatically
--                              (standardization of numerics, one-hot of STRINGs)
-- 4. Inspect features        → ML.FEATURE_INFO — verify BQ interpreted types correctly
-- 5. Evaluate                → ML.EVALUATE — check MAE, RMSE, R² on held-out data
-- 6. Predict                 → ML.PREDICT — score new or existing data
-- 7. Explain                 → ML.EXPLAIN_PREDICT — SHAP values, top_k_features
-- 8. Tune                    → hyperparameter search, regularization to prevent overfitting
--
-- Key decisions that affect model quality:
-- → feature selection (what to include)
-- → type casting (categorical vs numerical)
-- → data quality filters (fare=0, NULL tips)
-- → regularization strength (l1/l2 tuning)
-- → these are data/feature engineering decisions, not just ML decisions
--   which is exactly why DE and ML overlap here