library(fredr)
library(dplyr)
library(tidyr)
library(purrr)
library(zoo) 

# Set FRED API key
fredr_set_key("ae58a77f9383ad8ed12a84122eaa71e6") 

#30 years of data
start_date <- Sys.Date() - 365 * 30
end_date <- Sys.Date()

# List of variables 
variables <- list(
  "GDP" = "GDPC1",
  "CPI" = "CPIAUCSL",
  "Crude_Oil" = "DCOILWTICO",
  "Interest_Rate" = "FEDFUNDS",
  "Unemployment" = "UNRATE",
  "Trade_Balance" = "BOPGSTB",
  "Retail_Sales" = "RSAFS",
  "Housing_Starts" = "HOUST",
  "Capacity_Utilization" = "TCU",
  "Industrial_Production" = "INDPRO",
  "Nonfarm_Payrolls" = "PAYEMS",
  "PPI" = "PPIACO",
  "Core_PCE" = "PCEPILFE",
  "New_Orders_Durable_Goods" = "DGORDER",
  "Three_Month_Treasury_Yield" = "DTB3",
  "Consumer_Confidence_Index" = "UMCSENT",
  "New_Home_Sales" = "HSN1F",
  "Business_Inventories" = "BUSINV",
  "Construction_Spending" = "TTLCONS",
  "Wholesale_Inventories" = "WHLSLRIMSA",
  "Personal_Income" = "DSPIC96",
  "AAA" = "AAA",
  "BAA" = "BAA",
  "yield_spread" = "T10Y3MM"
  
)

# Function to retrieve and clean data
fetch_fred_data <- function(series_id, new_name) {
  fredr(series_id = series_id, observation_start = start_date, observation_end = end_date) %>%
    mutate(date = format(date, "%Y-%m")) %>%  # Convert to Year-Month format
    rename(!!new_name := value) %>%
    distinct(date, .keep_all = TRUE)  # Remove duplicates if any
}

# Fetch data for all variables
data_list <- lapply(names(variables), function(name) fetch_fred_data(variables[[name]], name))
# Merge all datasets on 'date'
final_data <- reduce(data_list, full_join, by = "date")
final_data <- final_data %>%
  select(date, GDP, CPI, Crude_Oil, Interest_Rate, Unemployment, Trade_Balance, 
         Retail_Sales,Housing_Starts, Capacity_Utilization,
         Industrial_Production, Nonfarm_Payrolls, PPI, Core_PCE,
         New_Orders_Durable_Goods, Three_Month_Treasury_Yield,
         Consumer_Confidence_Index, New_Home_Sales, Business_Inventories,
         Construction_Spending,
         Wholesale_Inventories, Personal_Income, AAA, BAA, yield_spread
  ) %>% mutate(junk_bond_spread = BAA - AAA) %>% select(-AAA) %>% select(-BAA) %>%
  arrange(desc(date)) %>% mutate(GDP = lag(GDP,1))


# Function to create lagged variables
lag_features <- function(data, lags = 4) {
  data %>%
    mutate(across(
      .cols = -date,  # Exclude the date column
      .fns = list(
        lag1 = ~ lag(., 1),
        lag2 = ~ lag(., 2),
        lag3 = ~ lag(., 3),
        lag4 = ~ lag(., 4)
      ),
      .names = "{.col}_{.fn}"  # Naming format: "GDP_lag1", "CPI_lag2", etc.
    ))
}

# Apply the function to your dataset
df_lagged <- lag_features(final_data, lags = 4)





write.csv(df_lagged, "../fred_data_4_lags.csv", row.names = FALSE)
