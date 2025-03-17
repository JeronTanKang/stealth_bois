library(fredr)
library(dplyr)
library(tidyr)
library(purrr)
library(zoo) 
library(lubridate)


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
final_data <- final_data %>% mutate(date = as.Date(paste0(date, "-01"))) %>%
  select(date, GDP, CPI, Crude_Oil, Interest_Rate, Unemployment, Trade_Balance, 
         Retail_Sales,Housing_Starts, Capacity_Utilization,
         Industrial_Production, Nonfarm_Payrolls, PPI, Core_PCE,
         New_Orders_Durable_Goods, Three_Month_Treasury_Yield,
         Consumer_Confidence_Index, New_Home_Sales, Business_Inventories,
         Construction_Spending,
         Wholesale_Inventories, Personal_Income, AAA, BAA, yield_spread
  ) %>% mutate(junk_bond_spread = BAA - AAA) %>% select(-AAA) %>% select(-BAA) %>%
  arrange(desc(date)) %>% mutate(GDP = lag(GDP,1))

#add a year_quarter col
final_data <- final_data %>%
  mutate(year_quarter = paste0(year(date), "Q", quarter(date)) 
  )  %>% select(date, year_quarter, everything())


# Function to apply Exponential Almon weights
exp_almon_weighted <- function(series, alpha = 0.9) {
  series <- na.omit(series)  # Remove NA values
  n <- length(series)
  
  if (n == 0) return(NA)  # Return NA if empty
  
  weights <- alpha^(seq(n, 1, by = -1) - 1)  # Generate weights
  weighted_sum <- sum(series * weights) / sum(weights)  # Apply weighting
  
  return(weighted_sum)
}

# Function to aggregate indicators from monthly to quarterly
aggregate_indicators <- function(df) {
  
  aggregation_rule <- list(
    "CPI" = "mean",
    "Crude_Oil" = "mean",
    "Interest_Rate" = "mean",
    "Unemployment" = "mean",
    "Trade_Balance" = "sum",
    "Retail_Sales" = "sum",
    "Housing_Starts" = "sum",
    "Capacity_Utilization" = "mean",
    "Industrial_Production" = "mean",
    "Nonfarm_Payrolls" = "sum",
    "PPI" = "mean",
    "Core_PCE" = "exp_almon",
    "New_Orders_Durable_Goods" = "sum",
    "Three_Month_Treasury_Yield" = "mean",
    "Consumer_Confidence_Index" = "mean",
    "New_Home_Sales" = "sum",
    "Business_Inventories" = "sum",
    "Construction_Spending" = "sum",
    "Wholesale_Inventories" = "sum",
    "Personal_Income" = "mean",
    "yield_spread" = "mean",
    "junk_bond_spread" = "mean"
  )
  
  
  gdp_data <- df %>%
    filter(!is.na(GDP)) %>%  # Remove NA values first
    group_by(year_quarter) %>%
    summarise(GDP = last(GDP)) %>%
    ungroup()
  
  # Aggregating indicators 
  indicators_data <- df %>%
    group_by(year_quarter) %>%
    summarise(across(
      names(aggregation_rule),
      ~ if (aggregation_rule[[cur_column()]] == "mean") mean(.x, na.rm = TRUE) else
        if (aggregation_rule[[cur_column()]] == "sum") sum(.x, na.rm = TRUE) else
          if (aggregation_rule[[cur_column()]] == "exp_almon") exp_almon_weighted(.x),
      .names = "{.col}"
    )) %>% ungroup()
  
  # Merging GDP and indicators
  quarterly_df <- full_join(gdp_data, indicators_data, by = "year_quarter")
  
  
  return(quarterly_df)
  }

          
                
                
              
final_data <- aggregate_indicators(final_data) 
final_data <- final_data %>% arrange(desc(year_quarter)) #arrange in desc date order







# Function to create lagged variables
lag_features <- function(data, lags = 4) {
  data %>%
    mutate(across(
      .cols = -year_quarter,  # Exclude the date column
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
df_lagged <- df_lagged %>% slice(-n()) #remove last row too many NANs




write.csv(df_lagged, "../fred_data_4_lags.csv", row.names = FALSE)
