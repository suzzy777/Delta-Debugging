#!/bin/bash

# Input file
input_file="new_results/VPC-Result_tfidf_sum-fixed.csv"
# Ensure the file exists
if [[ ! -f "$input_file" ]]; then
    echo "File not found: $input_file"
    exit 1
fi

# Extract unique values from the 5th column (Od-test) and process each group
# Group by project, sha, module, type, and od_test using cut and process each group
cut -d, -f1-5 "$input_file" | sort -u | while IFS=, read -r project sha module type od_test; do
    # Extract all rows matching the current group
    rows=$(grep -F "$project,$sha,$module,$type,$od_test" "$input_file")

#cut -d, -f5 "$input_file" | sort -u | while read -r project,sha,module,type,od_test,total_runtime,machine_runtime; do
    # Get all rows that match the current 'Od-test' group
 #   rows=$(grep -F "$od_test" "$input_file")

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
    echo "$project,$sha,$module,$type,$od_test,$average" >> new_results/DD_vpc_tfidf_sum.csv
done

