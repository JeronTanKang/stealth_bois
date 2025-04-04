"""
This file contains the `model_RF_bridge` function, which implements a Random Forest model pipeline for forecasting GDP growth and generating nowcasts. 
The process involves:
1. Forecasting macroeconomic indicators using an AR(p) model.
2. Aggregating and lagging the features.
3. Training a Random Forest model using selected features.
4. Generating nowcasts for missing GDP values based on the trained model.

The pipeline follows these steps:
- Feature selection via RFECV.
- Training the Random Forest model on preprocessed data.
- Forecasting GDP growth and converting it into GDP levels.
- Optionally saving the trained model.

Functions:
- `get_selected_features`: Selects important features using RFECV with time series split.
- `model_RF_bridge`: Full Random Forest pipeline for forecasting, aggregation, lagging, training, and nowcasting GDP.
"""

import pandas as pd
import numpy as np
from datetime import datetime
import joblib
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import train_test_split
from sklearn.model_selection import TimeSeriesSplit
from sklearn.feature_selection import RFECV
import os
import sys
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'Backend')))
from data_processing import aggregate_indicators, create_lag_features
#from model_ADL_bridge import record_months_to_forecast, forecast_indicators
from forecast_bridge_indicators import record_months_to_forecast, forecast_indicators
#pd.set_option("display.max_columns", None)
pd.reset_option("display.max_columns")


# #Actual data
file_path = "../Data/tree_df.csv"

# #Testing data 
# #file_path = "../Data/tree_df copy.csv"

df = pd.read_csv(file_path)
df["date"] = pd.to_datetime(df["date"], format="%Y-%m-%d")

# #Sort date in ascending order
df = df.sort_values(by='date', ascending= True)

# #Aggregate Data
df1 = aggregate_indicators(df)

# #Create lagged features
exclude_columns = ["date", "GDP", "dummy"]
df1 = create_lag_features(df1, exclude_columns, 4) 
#print("column names", df1.columns)

# #Sort date again 
df1 = df1.sort_values(by='date', ascending= True)

# #Drop NaN values created by lagging 
df1.dropna(inplace = True)

# #Drop 'Date' before defining X 
X = df1.drop(columns=["gdp_growth", "GDP", "date"])
Y = df1['gdp_growth']

def get_selected_features(X, Y, n_splits=5):
    """
    Runs RFECV using time series split on preprocessed and lagged X, Y data.
    Only the training set is used for feature selection.

    # Kelli pls specify here that this function is used only when u wna do feature selection. Once features are chosen, this part isnt run again to save computation time.

    Args:
        X (pd.DataFrame): Feature matrix containing the preprocessed and lagged macroeconomic data.
        Y (pd.Series): Target vector containing GDP growth values.
        n_splits (int): The number of splits for the time series cross-validation. Default is 5.

    Returns:
        list: A list of selected feature names after running RFECV.
    """

    # Time-based train-test split
    split_idx = int(len(X) * 0.8)
    X_train, Y_train = X.iloc[:split_idx], Y.iloc[:split_idx]

    rf_model = RandomForestRegressor(random_state=42)
    tscv = TimeSeriesSplit(n_splits=n_splits)

    rfecv = RFECV(
        estimator=rf_model,
        step=1,
        cv=tscv,
        scoring='neg_mean_squared_error',
        n_jobs=-1
    )

    #Fitting RFECV on training set 
    rfecv.fit(X_train, Y_train)


    # Fitting RFECV on training set 
    rfecv.fit(X_train, Y_train)

    selected_features = list(X_train.columns[rfecv.support_])

    # Desired simplified output
    print(f"Optimal number of features: {rfecv.n_features_}")
    print(f"These are your selected features: {selected_features}")


    return selected_features

#selected_features = get_selected_features(X, Y)

def model_RF_bridge(df):
    """
    Full RF pipeline: forecast monthly -> aggregate -> lag -> train -> nowcast.

    This function performs the following steps:
    1. Forecasts macroeconomic indicators using AR(p).
    2. Aggregates and lags the data.
    3. Trains a Random Forest model.
    4. Nowcasts missing GDP values.

    Args:
        df_raw (pd.DataFrame): Original raw DataFrame with monthly data.

    Returns:
        pd.DataFrame: DataFrame with nowcasted GDP growth and GDP values for the forecasted period.
    """

    # Hardcoded selected features
    selected_features = [
        'Unemployment', 'junk_bond_spread', 'Trade_Balance', 'Retail_Sales',
        'Capacity_Utilization', 'New_Orders_Durable_Goods', 'Business_Inventories',
        'Construction_Spending', 'junk_bond_spread_lag1', 'Crude_Oil_lag2',
        'Crude_Oil_lag4', 'Housing_Starts_lag2', 'Industrial_Production_lag3',
        'Nonfarm_Payrolls_lag3', 'New_Orders_Durable_Goods_lag1',
        'Consumer_Confidence_Index_lag2', 'Consumer_Confidence_Index_lag3',
        'New_Home_Sales_lag4', 'Business_Inventories_lag1', 'Construction_Spending_lag1'
    ]

    # 1. Forecast with AR(p) and preprocess
    df = df.sort_values(by='date', ascending=True)
    df_model = forecast_indicators(df)
    df_model = aggregate_indicators(df_model)
    df_model = create_lag_features(df_model, exclude_columns=["date", "GDP"], max_lag=4)
    df_model = df_model.sort_values(by='date', ascending=True)

    # 2. Clean up any problematic rows
    df_model = df_model[~((df_model["date"].dt.year == 1995) & (df_model.isna().any(axis=1)))]
    df_model = df_model[~((df_model["date"] == "1996-03-31") & (df_model.isna().any(axis=1)))]

    # 3. Subset to relevant features
    df_model = df_model[['date', 'GDP', 'gdp_growth'] + selected_features]

    # 4. Prepare training data
    df_model_train = df_model.dropna()
    X = df_model_train.drop(columns=["GDP", "gdp_growth", "date"])
    Y = df_model_train["gdp_growth"]

    # 5. Train model
    final_rf_model = RandomForestRegressor(random_state=42)
    final_rf_model.fit(X, Y)


    # 6. Nowcast for missing quarters
    recent_quarters_mask = df_model.index >= df_model.index[-4]
    nowcast_mask = (df_model["GDP"].isna()) | ((df_model["gdp_growth"].isna()) & recent_quarters_mask)
    forecast_df = df_model[nowcast_mask].copy()

    nowcast_results = None
    if not forecast_df.empty:
        last_known_idx = df_model[df_model["GDP"].notna()].index[-1]
        last_actual_gdp = df_model.loc[last_known_idx, "GDP"]

        X_forecast = forecast_df[selected_features]
        predicted_growth = final_rf_model.predict(X_forecast)

        predicted_gdp = []
        for growth in predicted_growth:
            next_gdp = last_actual_gdp * np.exp(growth / 400)
            predicted_gdp.append(next_gdp)
            last_actual_gdp = next_gdp

        nowcast_results = forecast_df[["date"]].copy()
        nowcast_results["Nowcasted_GDP_Growth"] = predicted_growth
        nowcast_results["Nowcasted_GDP"] = predicted_gdp
    else:
        print(" No rows to nowcast.")

    return nowcast_results

if __name__ == "__main__":
    print(model_RF_bridge(df))
