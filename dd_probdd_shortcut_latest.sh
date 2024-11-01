
if [[ $1 == "" ]]; then
    echo "arg1 - full path to the test order (e.g., failingorders_vp.csv)"
    exit
fi

if [[ $2 == "" ]]; then
    echo "arg2 - full path to the test ground-truth (e.g., VP/VPC/BSS)"
    exit
fi

# File paths
runtime_file="/home/mpious/predicting-flakies/Unbalanced/PerProj_Unbalanced_no_Comments/script/combruntimes/final_all_runtimes2.csv"
overhead_file="/home/mpious/predicting-flakies/Unbalanced/PerProj_Unbalanced_no_Comments/script/latest_data/average_overhead.csv"
ground_truth_dir="/home/mpious/predicting-flakies/Unbalanced/PerProj_Unbalanced_no_Comments/"

currentDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
mkdir -p "logs" "Result-Delta"

resultFileName="Result-Delta/$2-Result_probdd.csv"
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


delta_debug() {
    local elements=("$@")

    # Step 1: Initialize probability for each element
    declare -A probabilities
    local len=${#elements[@]}
    for elem in "${elements[@]}"; do
        probabilities["$elem"]=$(awk "BEGIN {print 1 / $len}")
    done

    echo "Starting Probabilities: ${probabilities[@]}"

    while true; do
        len=${#elements[@]}

        # Step 2: Check if any element has a probability of 1
        local found=0
        for elem in "${elements[@]}"; do
            if (( $(echo "${probabilities[$elem]} == 1" | bc -l) )); then
                echo "Polluter identified: $elem with probability 1"
                found=1
                return
            fi
        done
        [[ $found -eq 1 ]] && break

        # Step 3: Randomly split elements with non-zero probability into two chunks
        local chunk1=()
        local chunk2=()
        for elem in "${elements[@]}"; do
            if (( ${#chunk1[@]} < len / 2 )); then
                chunk1+=("$elem")
            else
                chunk2+=("$elem")
            fi
        done


        # If there's only one element left in the non-zero probability chunk, check if it's a polluter
        if [[ ${#chunk1[@]} -eq 1 ]]; then
            echo "Testing single remaining element: ${chunk1[0]}"
            making_chunks "log-single-element.txt" "${chunk1[0]}"
            read polluter_found total_runtime <<< $(calculate_runtime "$od_testName" "log-single-element.txt" "$total_runtime")
            updating_runtime

            if [[ $polluter_found == "true" ]]; then
                probabilities["${chunk1[0]}"]=1
                echo "Single remaining element ${chunk1[0]} identified as polluter."
                return
            else
                echo "Single remaining element ${chunk1[0]} is not a polluter."
                # Optionally, set the probability to 0 if we confirm it's not a polluter
                probabilities["${chunk1[0]}"]=0
                elements=("${elements[@]/${chunk1[0]}}")  # Remove non-polluter element from elements array
            fi
        fi


        echo "Testing Chunk 1: ${chunk1[*]}"
        making_chunks "log-chunk1.txt" "${chunk1[@]}"
        read polluter_found total_runtime <<< $(calculate_runtime "$od_testName" "log-chunk1.txt" "$total_runtime")
        updating_runtime

        if [[ $polluter_found == "true" ]]; then
            # Step 4: Set probabilities of elements in chunk2 to 0
            for elem in "${chunk2[@]}"; do
                probabilities["$elem"]=0
            done
            # Update the elements array to include only those in chunk1 (possible polluters)
            elements=("${chunk1[@]}")
            echo "Polluter found in chunk 1, updating elements to chunk1 for further splitting."
        else
            # Step 5: Update probabilities for chunk2 elements based on the result of chunk1
            local prod=1
            for elem in "${chunk1[@]}"; do
                prod=$(awk "BEGIN {print $prod * (1 - ${probabilities[$elem]})}")
            done
            local denom=$(awk "BEGIN {print 1 - $prod}")
            echo "Denom-----------------------$denom"
            for elem in "${chunk2[@]}"; do
                probabilities["$elem"]=$(awk "BEGIN {print ${probabilities[$elem]} / $denom}")
            done
            # Update the elements array to include only those in chunk2 (possible polluters)
            elements=("${chunk2[@]}")
            echo "Polluter not found in chunk 1, updating elements to chunk2 for further splitting."
        fi

        # Step 6: Check if no polluter was found in either chunk
        if [[ $polluter_found != "true" ]] && [[ $(echo "$prod == 1" | bc -l) -eq 1 ]]; then
            echo "No polluter found in either chunk."
            break
        fi

        echo "Updated Probabilities: ${probabilities[@]}"
    done
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
#    if [[ "$found_polluter" != "" ]]; then
#        echo "Polluter found: $found_polluter"
#        exit 1
#    else
#        echo "No polluter found."
#    fi

    rm -f logs/* prefix_file.txt
done < "$1"
