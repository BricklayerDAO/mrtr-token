from datetime import datetime

timestamps = []

dates = [
    datetime(2023, 11, 25),
    datetime(2024, 2, 25),
    datetime(2024, 5, 24),
    datetime(2024, 8, 29),
]

while len(timestamps) < 80:
    dates = [
        d.replace(year=d.year+1)
        for d in dates
    ]
    timestamps.extend(d.timestamp() for d in dates)

print(timestamps) # TODO: Check differences