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

### Function to Extract Classes and Their Methods ###
extract_classes_and_methods() {
    declare -A class_methods_map
    for elem in "$@"; do
        # Assuming elements are in the format FullyQualifiedClassName.methodName
        class_name="${elem%.*}"
        method_name="${elem##*.}"
        if [[ -z "${class_methods_map[$class_name]}" ]]; then
            class_methods_map[$class_name]="$method_name"
        else
            class_methods_map[$class_name]+=" $method_name"
        fi
    done

    echo "${!class_methods_map[@]}"  # Return list of class names
}

### Delta Debug Function (Updated with Class and Method Level Delta Debugging) ###
delta_debug() {
    local level="$1"      # 'class' or 'method'
    shift
    local elements=("$@")

    local n=2  # Minimum chunk size
    local len=${#elements[@]}
    echo "Elem count : $len"

    echo "Level: $level"
    declare -A class_methods

    # Process each element, assuming format "package.Class.method"
    for element in "${elements[@]}"; do
        # Extract the class name (everything before the last dot)
        class_name=$(echo "$element" | sed 's/\(.*\)\..*/\1/')

        # Store fully qualified method names under their respective class
        class_methods["$class_name"]+="$element "
    done

    # Get all the class names
    local class_names=("${!class_methods[@]}")
    local class_count=${#class_names[@]}

    if [ "$class_count" -lt "$n" ]; then
        echo "Only one class remaining, entering method-level debugging."
        delta_debug_method "${elements[@]}"  # Method-level delta debugging
        return
    fi

    # Split the classes into two chunks based on the number of classes
    local mid=$(((class_count + 1) / 2))
    local chunk1=("${class_names[@]:0:$mid}")
    local chunk2=("${class_names[@]:$mid}")

    echo "Chunk 1 Classes:"
    for class in "${chunk1[@]}"; do
        echo "$class"
    done

    echo "Chunk 2 Classes:"
    for class in "${chunk2[@]}"; do
        echo "$class"
    done

    # Combine methods from chunk1 classes
    local methods_chunk1=()
    for class in "${chunk1[@]}"; do
        methods_chunk1+=(${class_methods[$class]})
    done

    # Combine methods from chunk2 classes
    local methods_chunk2=()
    for class in "${chunk2[@]}"; do
        methods_chunk2+=(${class_methods[$class]})
    done

    echo "Testing combined methods in Chunk 1..."
    making_chunks "log-${projName}-chunk1.txt" "${methods_chunk1[@]}"
    read polluter_found total_runtime <<< $(calculate_runtime "$od_testName" "log-${projName}-chunk1.txt" "$total_runtime")
    updating_runtime

    if [[ $polluter_found == "true" ]]; then
        echo "Polluter found in Chunk 1. Refining within Chunk 1."
        delta_debug "class" "${methods_chunk1[@]}"  # Recursive call to further refine Chunk 1
        return
    fi

    echo "Testing combined methods in Chunk 2..."
    making_chunks "log-${projName}-chunk2.txt" "${methods_chunk2[@]}"
    read polluter_found total_runtime <<< $(calculate_runtime "$od_testName" "log-${projName}-chunk2.txt" "$total_runtime")
    updating_runtime

    if [[ $polluter_found == "true" ]]; then
        echo "Polluter found in Chunk 2. Refining within Chunk 2."
        delta_debug "class" "${methods_chunk2[@]}"  # Recursive call to further refine Chunk 2
        return
    fi

    echo "No polluter found in either chunk."
}

### Delta Debug Function for Methods ###
delta_debug_method() {
    local elements=("$@")
    local n=2  # Minimum chunk size
    local len=${#elements[@]}
    echo "Elem count (methods): $len"

    if [ "$len" -lt "$n" ]; then
        echo "Testing single method: ${elements[0]}"
        making_chunks "log-${projName}-single-method.txt" "${elements[@]}"
        read polluter_found total_runtime <<< $(calculate_runtime "$od_testName" "log-${projName}-single-method.txt" "$total_runtime")
        updating_runtime

        if [[ $polluter_found == "true" ]]; then
            echo "Polluter found in method: ${elements[0]}"
            found_polluter="${elements[0]}"
            return
        else
            echo "No polluter found in method: ${elements[0]}"
        fi
        return
    fi

    # Split the methods into two chunks
    local mid=$(((len + 1) / 2))
    local chunk1=("${elements[@]:0:$mid}")
    local chunk2=("${elements[@]:$mid}")

    echo "Chunk 1 Methods:"
    for method in "${chunk1[@]}"; do
        echo "$method"
    done

    echo "Chunk 2 Methods:"
    for method in "${chunk2[@]}"; do
        echo "$method"
    done

    # Test chunk1
    echo "Testing Chunk 1 methods..."
    making_chunks "log-${projName}-method-chunk1.txt" "${chunk1[@]}"
    read polluter_found total_runtime <<< $(calculate_runtime "$od_testName" "log-${projName}-method-chunk1.txt" "$total_runtime")
    updating_runtime

    if [[ $polluter_found == "true" ]]; then
        echo "Polluter found in Chunk 1. Refining within Chunk 1."
        delta_debug_method "${chunk1[@]}"  # Recursive call to further refine Chunk 1
        return
    fi

    # Test chunk2
    echo "Testing Chunk 2 methods..."
    making_chunks "log-${projName}-method-chunk2.txt" "${chunk2[@]}"
    read polluter_found total_runtime <<< $(calculate_runtime "$od_testName" "log-${projName}-method-chunk2.txt" "$total_runtime")
    updating_runtime

    if [[ $polluter_found == "true" ]]; then
        echo "Polluter found in Chunk 2. Refining within Chunk 2."
        delta_debug_method "${chunk2[@]}"  # Recursive call to further refine Chunk 2
        return
    fi

    echo "No polluter found in either chunk of methods."
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
