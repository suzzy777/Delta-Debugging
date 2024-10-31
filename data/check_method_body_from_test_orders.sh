#$1=passingorder_brittle.csv
#$2=BSS/VP/VPC
if [[ $2 == "VP" ]]; then
    dir_that_contains_meth_body="../Bala-Proj/predicting-flakies/Unbalanced/PerProj_Unbalanced_no_Comments/VP_Per_Victim/"
elif [[ $2 == "BSS" ]]; then
    dir_that_contains_meth_body="../Bala-Proj/predicting-flakies/Unbalanced/PerProj_Unbalanced_no_Comments/BSS_Per_Brittle/"
elif [[ $2 == "VPC" ]]; then
    dir_that_contains_meth_body="../../../Unbalanced/PerProj_Unbalanced_no_Comments/VC/"
fi

echo "proj,sha,module,od_test_category,od_test,new_prefix_test_orders" > "${2}_updated_File.csv"
while read line; do
    if [[ ${line} =~ ^\# ]]; then
        echo "Line starts with Hash $line"
        continue
    fi  
    proj=$(echo $line | cut -d',' -f1)
    sha=$(echo $line | cut -d',' -f2)
    module=$(echo $line | cut -d',' -f3)
    od_test_category=$(echo $line | cut -d',' -f4)
    od_test=$(echo $line | cut -d',' -f5)
    if [[ $2 == "VPC" ]]; then
        polluter_test=$(echo $line | cut -d',' -f6) 
        prefix_test_orders=$(echo $line | cut -d',' -f7)
        od_test="$od_test,$polluter_test"
    else
        prefix_test_orders=$(echo $line | cut -d',' -f6)
    fi
    echo $od_test
    new_prefix_test_orders=""
    # Set the Internal Field Separator to semicolon to loop through each test
    IFS=';'
    for relevant_test in $prefix_test_orders; do
        if [[ "$od_test" == *"$relevant_test"* ]]; then
            echo "$relevant_test exists in $od_test" # if od_test or polluter exists in the order_list
            new_prefix_test_orders="${new_prefix_test_orders};$relevant_test"
        else
            pair_found=$(grep -r ",$od_test,$relevant_test," $dir_that_contains_meth_body | wc -l)
            if [[ $pair_found -gt 0 ]]; then
               if [[ $new_prefix_test_orders == "" ]]; then
                   new_prefix_test_orders=$relevant_test
                   #echo "new_orders=$new_prefix_test_orders"
               else
                   #echo "Adding semicolon"
                   new_prefix_test_orders="${new_prefix_test_orders};${relevant_test}"
                   #echo "new_orders=$new_prefix_test_orders"
               fi
            fi
        fi
    done
    echo "$proj,$sha,$module,$od_test_category,$od_test,$new_prefix_test_orders" >> "${2}_updated_File.csv"
    # Reset IFS to default value (space, tab, newline)
    IFS=$' \t\n'

    exit
    #echo $od_test
    #echo $test_order
    #exit
   
done < $1


