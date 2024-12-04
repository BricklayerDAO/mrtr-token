import datetime
import calendar

def generate_gmt_timestamps(start_year=2024, end_year=2044):
    # Define the target dates
    target_dates = [
        (3, 25),   # March 25th
        (6, 24),   # June 24th
        (9, 29),   # September 29th
        (12, 25)   # December 25th
    ]
    
    timestamps = []
    
    # Start with December 25, 2024
    initial_date = datetime.datetime(start_year, 12, 25, 0, 0, 0, tzinfo=datetime.timezone.utc)
    timestamps.append(int(initial_date.timestamp()))
    
    # Iterate through each year from 2025 to 2044
    for year in range(start_year + 1, end_year + 1):
        for month, day in target_dates:
            dt = datetime.datetime(year, month, day, 0, 0, 0, tzinfo=datetime.timezone.utc)
            timestamps.append(int(dt.timestamp()))
    
    return timestamps

timestamps = generate_gmt_timestamps()
print(timestamps)
print(f"Total timestamps generated: {len(timestamps)}")
