#!/bin/bash

# Input file
input_file="Result-Delta-original/BSS-Result_hdd.csv"

# Ensure the file exists
if [[ ! -f "$input_file" ]]; then
    echo "File not found: $input_file"
    exit 1
fi

# Extract unique values from the 5th column (Od-test) and process each group
cut -d, -f5 "$input_file" | sort -u | while read -r od_test; do
    # Get all rows that match the current 'Od-test' group
    rows=$(grep -F "$od_test" "$input_file")

    # Count the number of matching rows
    count=$(echo "$rows" | wc -l)

    # Calculate the total sum of the 6th and 7th columns
    sum=$(echo "$rows" | awk -F, '{sum += $6 + $7} END {print sum}')

    # Calculate the average sum
    if [[ $count -gt 0 ]]; then
        average=$(echo "scale=2; $sum / $count" | bc -l)
    else
        average=0
    fi

    # Print the result in CSV format
    echo "$od_test,$average" >> DD_hdd_bss.csv
done
