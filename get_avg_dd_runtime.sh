#!/bin/bash                                                                                                                                                           

# Input file                                                                                                                                                          
input_file="new_results/DD_vp_orig_neworders.csv"
# Ensure the file exists                                                                                                                                              
if [[ ! -f "$input_file" ]]; then
    echo "File not found: $input_file"
    exit 1
fi



# Group by project, sha, and module using cut, and calculate the average runtime
cut -d, -f1-3 "$input_file" | sort -u | while IFS=, read -r project sha module; do
    # Extract all rows matching the current group
    rows=$(grep -F "$project,$sha,$module" "$input_file")

    # Count the number of matching od_test rows
    count=$(echo "$rows" | wc -l)

    # Calculate the total sum of the runtimes from the 6th column
    sum=$(echo "$rows" | awk -F, '{sum += $6} END {print sum}')
    echo "Sum: $sum"
    # Calculate the average runtime
    if [[ $count -gt 0 ]]; then
        average=$(echo "scale=2; $sum / $count" | bc -l)
	echo "Average: $average"
    else
        average=0
    fi

    # Output the result in the required format
    echo "$project,$sha,$module,$average" >> new_results/module_dd_original_vp.csv
done
