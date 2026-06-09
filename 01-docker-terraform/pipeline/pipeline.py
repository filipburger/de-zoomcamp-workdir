import sys
import pandas as pd

print('Arguments:', sys.argv[1:])


df = pd.DataFrame({"day": [1,2], "num_passengers": [3,4]})
month = sys.argv[1]
df['month'] = month
print(df.head())
df.to_parquet(f"output/{month}.parquet")
 
print(f"Hello from the pipeline! Month={month}")