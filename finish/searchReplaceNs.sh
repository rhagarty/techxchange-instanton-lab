#!/bin/bash

default_namespace="dev-[Your initial]"
default_service_acct="instanton-sa-[Your initial]"

if [ "$#" -eq 0 ]; then
    old_namespace=$default_namespace
elif [ "$#" -eq 1 ]; then
    old_namespace=$1
else
    echo "Usage: $0 [<old_namespace>]"
    exit 1
fi

new_namespace=$CURRENT_NS
selected_files=(./deploy-with-instanton.yaml ./deploy-without-instanton.yaml)
changes=0

if [[ -z "${new_namespace}" ]]; then
    echo "Warning: The CURRENT_NS variable is empty. Please verify the export command in step 6. The script will now terminate."
    exit 1
fi

for file in "${selected_files[@]}"; do
    if [ "$old_namespace" == "dev-[Your initial]" ]; then
        sed -i "s/dev-\[Your initial\]/$new_namespace/g" "$file"
    else 
        sed -i "s/$old_namespace/$new_namespace/g" "$file"
    fi
    sed -i "s/instanton-sa-\[Your initial\]/instanton-sa-$new_namespace/g" "$file"
    
    changes=$((changes + 1))
done
echo "Changed $changes files to replace $old_namespace with $new_namespace"