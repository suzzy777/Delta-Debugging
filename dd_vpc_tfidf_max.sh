#!/usr/bin/env bash
if [[ $1 == "" || $2 == "" ]]; then
    echo "arg1 - full path to the test order (eg. vp_failing_orders.csv /  bss_passing_orders.csv / combined_final_vpc.csv)"
    echo "arg2 - full path to the test ground-truth (eg. VP/VPC/BSS)"
    #$3=true_victim_polluter_pair.csv
    exit
fi

runtime_file="../weightedDD/predicting-flakies/Unbalanced/PerProj_Unbalanced_no_Comments/script/combruntimes/final_all_runtimes2.csv"
overhead_file="../weightedDD/predicting-flakies/Unbalanced/PerProj_Unbalanced_no_Comments/script/latest_data/average_overhead.csv"

ground_truth_dir="../weightedDD/predicting-flakies/Unbalanced/PerProj_Unbalanced_no_Comments/"

currentDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

if [ ! -d "logs" ] 
then
    mkdir "logs"
fi

Results="Result-Delta-vpc"
if [ ! -d "$Results" ] 
then
    mkdir "$Results"
fi

resultFileName="$Results/$2-Result_tfidf_max-fixed.csv"
echo "Project-name,SHA,Module,Od-test,Polluter,Total-Runtime,Time-to-run-the-last-one" > "$currentDir/$resultFileName"

min_number() {
    printf "%s\n" "$@" | sort -g | head -n1
}

calculate_runtime_by_checking_true_cleaner()
{
    local od_testName="$1"
    local log_file="$2"
    local total_runtime="$3"
    local delta_debug_starts_time=$4
    local cleaner_found="General_Test" #Not_Polluter_Not_Cleaner
    
    polluter_count=0
    cleaner_count=0
    entered="false" 
    othertest_item="NA"
    while IFS= read -r otherchunk_item; do # We are traversing the list from end to begin
       #echo "otherchunk_item= $otherchunk_item"
       if [[ $entered == "false" ]]; then
           polluter_count=$(grep "$od_testName,$otherchunk_item" "../weightedDD/Predict-Flakies/Per_project_result/Delta-Debugging/true_victim_polluter_pair.csv" | wc -l) #if the item is polluter for this victim, then polluter should be found
           cleaner_count=$(grep "$od_testName,$polluter_testName,$otherchunk_item,1," "$ground_truth_filename" | wc -l) #search into ground_truth
           #cleaner_line=$(grep "$od_testName,$polluter_testName,$otherchunk_item,1" "$ground_truth_filename")
           #echo "$cleaner_line" >&2
           if [[ $cleaner_count -gt 0 && $polluter_count -eq 0 ]]; then
               cleaner_found="true" #test_pass
               entered="true" 
               othertest_item=${otherchunk_item}
           elif [[ $polluter_count -gt 0 && $delta_debug_starts_time -eq 1 ]]; then  #IF it is the first time and finds polluter at the end
               cleaner_found="false" #test_fail, meaning that polluter is at the end of the order
               entered="true" 
               othertest_item=${otherchunk_item}
           fi
       fi
       runtime=$(grep ",$otherchunk_item," ${runtime_file} | cut -d',' -f5)
       total_runtime=$(awk -v total="$total_runtime" -v run="$runtime" 'BEGIN {printf "%.9f", total + run}')
    done < <(tac "$currentDir/logs/${log_file}")

    echo "$cleaner_found $total_runtime $othertest_item"
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

# making_chunks()
# {
#     local file_name=$1
#     shift  # Remove the first argument (file_name)
#     local elements=("$@")
#     for elem in "${elements[@]}"
#     do
#         if [ ! -z $elem ];
#         then
#             sed -n "$elem"p $resultLocationsFile >> "$currentDir/logs/${file_name}" #all_subset of test names
#         fi
#     done
# }

count=0

delta_debug() {
    # local array_name="$1[@]"
    # local n=$2
    # local elements=("${!array_name}")
    # count=$((count+1))
    # echo "STARTING ELEMENTS: ${elements[*]}"
    # len=${#elements[@]}
    
    local elements=("$@")  # Capture all arguments directly as an array
    local n=2  # Minimum chunk size
    local len=${#elements[@]}  # Length of the elements array

    echo "STARTING ELEMENTS: ${elements[*]}"
    
    if [ $len -lt $n ]; then
        echo "ENTERING..."
        making_chunks "log-${projName}-when-one-item.txt" "${elements[@]}"
        read othertest_found total_runtime othertest_item <<< $(calculate_runtime_by_checking_true_cleaner "${od_testName}" "log-${projName}-when-one-item.txt" "$total_runtime" "$count_to_call_delta_debug")
	echo "CLEANER: $othertest_item"
        
        # Update runtime for this specific test
        od_test_runtime=$(grep ",$od_testName," ${runtime_file} | cut -d',' -f5)
        mvn_overhead=$(grep "$slug,$sha,$module" ${overhead_file} | cut -d',' -f6)
        total_runtime=$(awk -v total="$total_runtime" -v od_test="$od_test_runtime" -v mvn_overhead="$mvn_overhead" 'BEGIN {printf "%.9f", total + od_test + mvn_overhead}')

        if [[ $othertest_found != "true" && $considered_obo != "true" ]]; then
            echo "NOT TRUE CLEANER ============="
        else   
            end_time=$(date +%s.%N)
            take=$(echo "scale=2; ${end_time} - ${start}" | bc)
            take=$(echo $take | awk '{printf("%.2f\n", $1) }')
            return
        fi
    fi

    # Split the array into two chunks and calculate their TF-IDF scores
    local mid=$(((len + 1) / 2))
    local chunk1=("${elements[@]:0:$mid}")
    local chunk2=("${elements[@]:$mid}")

    echo "Chunk 1: ${chunk1[@]}"
    echo "Chunk 2: ${chunk2[@]}"

    # Calculate TF-IDF scores for both chunks to determine exploration order
    avg_tfidf_chunk1=$(python3 vpc_tfidf_scores_max.py "$ground_truth_filename" "$od_testName" "$polluter_testName" "${chunk1[@]}")
    avg_tfidf_chunk2=$(python3 vpc_tfidf_scores_max.py "$ground_truth_filename" "$od_testName" "$polluter_testName" "${chunk2[@]}")

    echo "Chunk 1 score: $avg_tfidf_chunk1"
    echo "Chunk 2 score: $avg_tfidf_chunk2"
    # Decide exploration order based on TF-IDF score
    if (( $(echo "$avg_tfidf_chunk1 > $avg_tfidf_chunk2" | bc -l) )); then
        explore_first=("${chunk1[@]}")
        explore_second=("${chunk2[@]}")
        echo "Exploring Chunk 1 first."
    else
        explore_first=("${chunk2[@]}")
        explore_second=("${chunk1[@]}")
        echo "Exploring Chunk 2 first."
    fi

    count_to_call_delta_debug=$((count_to_call_delta_debug + 1))
    # Explore the first chunk
    making_chunks "log-${projName}-chosen-chunk.txt" "${explore_first[@]}"
    read othertest_found total_runtime othertest_item <<< $(calculate_runtime_by_checking_true_cleaner "$od_testName" "log-${projName}-chosen-chunk.txt" "$total_runtime" "$count_to_call_delta_debug")
    echo "CLEANER: $othertest_item"
    # OBO condition: Check if a polluter is found after a cleaner
    if [[ $othertest_found == "false" ]]; then
        obo_res=$(grep  ",$od_testName,$polluter_testName," "../weightedDD/Predict-Flakies/Per_project_result/scripts/Result/OBO/OBO_AVG_Data/Result_isVictimPolluterCleanerPair_Strategy_NA.csv")
        obo_time=$(echo $obo_res | rev | cut -d',' -f1 | rev)
        total_runtime=$obo_time
        considered_obo="true"
        return
    elif [[ $othertest_found == "true" ]]; then
        echo "Cleaner found in the chosen chunk."
        delta_debug "${explore_first[@]}"
        return
    fi

    # Explore the second chunk if needed
    making_chunks "log-${projName}-remaining-chunk.txt" "${explore_second[@]}"
    read othertest_found total_runtime othertest_item <<< $(calculate_runtime_by_checking_true_cleaner "$od_testName" "log-${projName}-remaining-chunk.txt" "$total_runtime")
    echo "CLEANER: $othertest_item"

    # Apply OBO condition for the second chunk
    if [[ $othertest_found == "false" ]]; then
        obo_res=$(grep  ",$od_testName,$polluter_testName," "../weightedDD/Predict-Flakies/Per_project_result/scripts/Result/OBO/OBO_AVG_Data/Result_isVictimPolluterCleanerPair_Strategy_NA.csv")
        obo_time=$(echo $obo_res | rev | cut -d',' -f1 | rev)
        total_runtime=$obo_time
        considered_obo="true"
        return
    elif [[ $othertest_found == "true" ]]; then
        echo "Cleaner found in this chunk."
        delta_debug "${explore_second[@]}"
        return
    fi
}

row_count=0
while IFS= read -r line
    do
    if [[ ${line} =~ ^\# ]]; then
        echo "Line starts with Hash $line"
        continue
    fi
    total_runtime=0
    considered_obo="false"
    slug=$(echo $line | cut -d',' -f1)
    sha=$(echo $line | cut -d',' -f2)
    module=$(echo $line | cut -d',' -f3)
    testtype=$(echo $line | cut -d',' -f4)
    od_testName=$(echo $line | cut -d',' -f5) #victim/brittle
    echo "OD TEST: $od_testName"
    if [[ $2 == "VPC" ]]; then
        polluter_testName=$(echo $line | cut -d',' -f6) #polluter
	echo "POLLUTER TEST: $polluter_testName" 
	all_prefix_init=$(echo $line | cut -d',' -f7)
        echo "$all_prefix_init" | tr ';' '\n' > tmp
        od_test_pos=$(grep -wn "$od_testName" tmp | cut -d: -f1)
        echo "OD TEST POSITION: $od_test_pos"
        polluter_test_pos=$(grep -wn "$polluter_testName" tmp | cut -d: -f1)
        echo "POLLUTER TEST POSITION: $polluter_test_pos"
        if [[ $polluter_test_pos -gt $od_test_pos ]]; then
            echo "Need to do OBO"
            obo_res=$(grep  ",$od_testName,$polluter_testName," "../weightedDD/Predict-Flakies/Per_project_result/scripts/Result/OBO/OBO_AVG_Data/Result_isVictimPolluterCleanerPair_Strategy_NA.csv") #OBO result file
            obo_time=$(echo $obo_res | rev | cut -d',' -f1 | rev)
            total_runtime=$obo_time
            considered_obo="true"
	    all_prefix="" 
        else
	    echo "Polluter before victim!"
            # Convert the range between od_test_pos and polluter_test_pos back to a semicolon-separated string
            #all_prefix=$(sed -n "$((pol_test_pos + 1)),$((od_test_pos - 1))p" tmp | paste -sd ';' -)
            echo $polluter_test_pos
            echo $od_test_pos
            all_prefix=$(sed -n "$((polluter_test_pos + 1)),$((od_test_pos - 1))p" tmp | tr '\n' ';' | sed 's/;$//')
            echo "PREFIX: $all_prefix"
            #exit
        fi
        #exit

    else
        all_prefix=$(echo $line | cut -d',' -f6)
    fi    
    testName_for_file_name=$(echo $od_testName |sed 's;\[;\\[;') #adding slash if square bracket exits
    echo -n "${slug}" >> "$currentDir/$resultFileName"
    echo -n ",${sha}" >> "$currentDir/$resultFileName"
    echo -n ",${module}" >> "$currentDir/$resultFileName"
    echo -n ",${testtype}" >> "$currentDir/$resultFileName"
    echo -n ",${od_testName}" >> "$currentDir/$resultFileName"
    if [[ $2 == "VPC" ]]; then
        echo -n ",${polluter_testName}" >> "$currentDir/$resultFileName"
    fi

    # > prefix_file.txt  # Clear file
    # echo "$all_prefix" | tr ';' '\n' | sed '/^$/d' > prefix_file.txt

    echo "$all_prefix" | tr ';' '\n' > "tmp.txt" # need to remove the blank line at the end
    sed '/^$/d' tmp.txt > "prefix_file.txt"
    
    #rm "tmp.txt"
    if [[ $module != "." ]]; then
        projName=$(sed 's;/;.;g' <<< $module-${od_testName})
    else   
        projName=$(sed 's;/;.;g' <<< $subProj-${od_testName})
    fi 
    ground_truth_filename=""
    if [[ $2 == "VP" ]]; then
        ground_truth_filename=${ground_truth_dir}"VP_Per_Victim/VP_${slug}.csv"
    elif [[ $2 == "VPC" ]]; then
        ground_truth_filename=${ground_truth_dir}"VC/VC_${slug}.csv"
        #calculate runtime for <polluter>,<all_other_tests>,<victim> 
    elif [[ $2 == "BSS" ]]; then
        ground_truth_filename=${ground_truth_dir}"BSS_Per_Brittle/BSS_${slug}.csv"
    fi

    resultLocationsFile="prefix_file.txt"

    # locationCount=$(wc -l < $resultLocationsFile)	

    # count_to_call_delta_debug=0
    # arr=($(seq 1 $locationCount))
    # echo "Seq size= ${#arr[@]} "

    
    # full_start=$(date +%s.%N)
    # start=$(date +%s.%N)
    # if [[ $considered_obo == "false" ]]; then 
    #     delta_debug "${arr[@]}" #arr 2 0
    # fi
    # full_end=$(date +%s.%N)
    # take=$(echo "scale=2; ${full_end} - ${full_start}" | bc)
    # take=$(echo $take | awk '{printf("%.2f\n", $1) }')
    # echo "Saving ..."

    mapfile -t arr < "$resultLocationsFile"

    start=$(date +%s.%N)
    delta_debug "${arr[@]}"
    end=$(date +%s.%N)

    runtime=$(echo "$end - $start" | bc)

    if [[ $considered_obo == "true" ]]; then
        echo ",${total_runtime},${runtime},OBO" >> "$currentDir/$resultFileName"
    else
        echo ",${total_runtime},${runtime},DD" >> "$currentDir/$resultFileName"
    fi
    #exit
    if [[ $considered_obo == "false" ]]; then
      rm logs/*
    fi
    #rm logs/*
    rm "prefix_file.txt"
done < $1
