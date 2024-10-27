# #!/usr/bin/env bash

#!/usr/bin/env bash

# Validate input arguments
if [[ $1 == "" ]]; then
    echo "arg1 - full path to the test order (e.g., failingorders_vp.csv)"
    exit
fi

if [[ $2 == "" ]]; then
    echo "arg2 - full path to the test ground-truth (e.g., VP/VPC/BSS)"
    exit
fi

# File paths
runtime_file="predicting-flakies/Unbalanced/PerProj_Unbalanced_no_Comments/script/combruntimes/final_all_runtimes2.csv"
overhead_file="predicting-flakies/Unbalanced/PerProj_Unbalanced_no_Comments/script/latest_data/average_overhead.csv"
ground_truth_dir="predicting-flakies/Unbalanced/PerProj_Unbalanced_no_Comments/"

currentDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
mkdir -p "logs" "Result-Delta"

resultFileName="Result-Delta/$2-Result.csv"
echo "Project-name,SHA,Module,Type,Od-test,Total-Runtime,Time-to-run-the-last-one" > "$currentDir/$resultFileName"

# Track the polluter globally
found_polluter=""

### Calculate Runtime ###
calculate_runtime() {
    local od_testName="$1"
    local log_file="$2"
    local total_runtime="$3"
    local polluter_found="false"

    while read otherchunk_item; do
        polluter_count=$(grep "$od_testName,$otherchunk_item,1" "$ground_truth_filename" | wc -l)
        runtime=$(grep ",$otherchunk_item," ${runtime_file} | cut -d',' -f5)
        total_runtime=$(awk -v total="$total_runtime" -v run="$runtime" 'BEGIN {printf "%.9f", total + run}')
        
        if [[ ${polluter_count} -gt 0 ]]; then
            polluter_found="true"
            found_polluter="$otherchunk_item"
	    #echo "Found polluter: $found_polluter" >&2
        fi
    done < "$currentDir/logs/${log_file}"

    echo "$polluter_found $total_runtime" 
}

### Create Log Files with Chunks ###
making_chunks() {
    local file_name=$1
    shift
    local elements=("$@")
    > "$currentDir/logs/${file_name}"  # Clear file

    for elem in "${elements[@]}"; do
        [[ -n $elem ]] && grep -F "$elem" "$resultLocationsFile" >> "$currentDir/logs/${file_name}"
    done
}

### Update Runtime ###
updating_runtime() {
    od_test_runtime=$(grep ",$od_testName," ${runtime_file} | cut -d',' -f5)
    mvn_overhead=$(grep "$slug,$sha,$module" ${overhead_file} | cut -d',' -f6)
    total_runtime=$(awk -v total="$total_runtime" -v od_run="$od_test_runtime" -v mvn="$mvn_overhead" \
                    'BEGIN {printf "%.9f", total + od_run + mvn}')
}

### Delta Debug Function ###
delta_debug() {
    local elements=("$@")
    local n=2  # Minimum chunk size
    local len=${#elements[@]}

    echo "STARTING ELEMENTS: ${elements[*]}"

    # Base case: If chunk size is below threshold
    if [ "$len" -lt "$n" ]; then
        making_chunks "log-${projName}-when-one-item.txt" "${elements[@]}"
        read polluter_found total_runtime <<< $(calculate_runtime "$od_testName" "log-${projName}-when-one-item.txt" "$total_runtime")
        updating_runtime

        if [[ $polluter_found == "true" ]]; then
            echo "Polluter found for ${od_testName}: ${elements[*]}"
	    found_polluter="${elements[0]}"
            return
        fi
        return  # No polluter found in atomic chunk
    fi

    # Split the array into two chunks
    local mid=$(((len + 1) / 2))
    local chunk1=("${elements[@]:0:$mid}")
    local chunk2=("${elements[@]:$mid}")

    echo "Chunk 1: ${chunk1[@]}"
    echo "Chunk 2: ${chunk2[@]}"
  
    # Calculate average TF-IDF scores for both chunks
    avg_tfidf_chunk1=$(python3 new_tfidf_scores_avg.py "$ground_truth_filename" "$od_testName" "${chunk1[@]}")
    avg_tfidf_chunk2=$(python3 new_tfidf_scores_avg.py "$ground_truth_filename" "$od_testName" "${chunk2[@]}")

    echo "Average TF-IDF Scores - Chunk 1: $avg_tfidf_chunk1, Chunk 2: $avg_tfidf_chunk2"

    # Decide the order of exploration based on TF-IDF score
    if (( $(echo "$avg_tfidf_chunk1 > $avg_tfidf_chunk2" | bc -l) )); then
        explore_first=("${chunk1[@]}")
        explore_second=("${chunk2[@]}")
        echo "Exploring Chunk 1 first."
    else
        explore_first=("${chunk2[@]}")
        explore_second=("${chunk1[@]}")
        echo "Exploring Chunk 2 first."
    fi

    echo "Exploring Chunk: ${explore_first[@]}"

    # Explore the first chunk
    making_chunks "log-${projName}-chosen-chunk.txt" "${explore_first[@]}"
    read polluter_found total_runtime <<< $(calculate_runtime "$od_testName" "log-${projName}-chosen-chunk.txt" "$total_runtime")
    updating_runtime

    if [[ $polluter_found == "true" ]]; then
        echo "Polluter found in the chosen chunk."
        delta_debug "${explore_first[@]}"
        return
    fi

    echo "No polluter in the chosen chunk. Looking for polluter in the remaining chunk."
    # Explore the second chunk if the first one passes
    making_chunks "log-${projName}-remaining-chunk.txt" "${explore_second[@]}"
    read polluter_found total_runtime <<< $(calculate_runtime "$od_testName" "log-${projName}-remaining-chunk.txt" "$total_runtime")
    updating_runtime

    if [[ $polluter_found == "true" ]]; then
        echo "Polluter found in this chunk."
        delta_debug "${explore_second[@]}"
        return
    fi

    echo "No polluter found in either chunk."
}
### Main Loop ###
while IFS= read -r line; do
    [[ ${line} =~ ^\# ]] && { echo "Line starts with Hash $line"; continue; }

    total_runtime=0
    slug=$(echo $line | cut -d',' -f1)
    sha=$(echo $line | cut -d',' -f2)
    module=$(echo $line | cut -d',' -f3)
    testtype=$(echo $line | cut -d',' -f4)
    od_testName=$(echo $line | cut -d',' -f5)
    all_prefix=$(echo $line | cut -d',' -f6)

    echo -n "${slug},${sha},${module},${testtype},${od_testName}" >> "$currentDir/$resultFileName"

#    echo "$all_prefix" | tr ';' '\n' > "prefix_file.txt"
    echo "$all_prefix" | tr ';' '\n' | sed '/^$/d' > "prefix_file.txt"

    projName=$(sed 's;/;.;g' <<< "${module}-${od_testName}")

    if [[ $2 == "VP" ]]; then
        ground_truth_filename="${ground_truth_dir}VP_Per_Victim/VP_${slug}.csv"
    elif [[ $2 == "VPC" ]]; then
        ground_truth_filename="${ground_truth_dir}VPC_Per_Victim/VPC_${slug}.csv"
    elif [[ $2 == "BSS" ]]; then
        ground_truth_filename="${ground_truth_dir}BSS_Per_Brittle/BSS_${slug}.csv"
    fi

    resultLocationsFile="prefix_file.txt"
    mapfile -t arr < "$resultLocationsFile"

    start=$(date +%s.%N)
    delta_debug "${arr[@]}"
    end=$(date +%s.%N)

    runtime=$(echo "$end - $start" | bc)
    echo ",${total_runtime},${runtime}" >> "$currentDir/$resultFileName"

    [[ "$found_polluter" != "" ]] && echo "Polluter found: $found_polluter" || echo "No polluter found."

    rm -f logs/* prefix_file.txt
done < "$1"
