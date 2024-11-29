const dateOffsets = [
  { month: 11, day: 25 }, // December 25
  { month: 2, day: 25 },  // March 25
  { month: 5, day: 24 },  // June 24
  { month: 8, day: 29 }   // September 29
];

const totalDates = 80; // Total number of dates (20 years * 4 dates/year)
const dates: Date[] = [];

let startDate = new Date(2024, 11, 25, 0, 0, 0); // Starting from December 25, 2024
dates.push(startDate);

for (let i = 1; i < totalDates; i++) {
  const prevDate = dates[i - 1];
  const prevMonth = prevDate.getMonth();
  const prevDay = prevDate.getDate();

  // Find the index of the previous date in dateOffsets
  const prevIndex = dateOffsets.findIndex(
    (offset) => offset.month === prevMonth && offset.day === prevDay
  );

  // Calculate the next index in the dateOffsets array
  const nextIndex = (prevIndex + 1) % dateOffsets.length;
  let year = prevDate.getFullYear();
  const offset = dateOffsets[nextIndex];

  // Increment year if moving from December to the next years date
  if (prevMonth === 11 && offset.month < prevMonth) {
    year += 1;
  }

  const nextDate = new Date(year, offset.month, offset.day, 0, 0, 0);
  dates.push(nextDate);
}

// Output the timestamps at 00:00 hours for each date
dates.forEach((date) => {
  console.log(date.getTime());
});