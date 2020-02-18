#!/usr/bin/env bash

print_usage() {
    echo "Script performs the following: "
    echo "(1) Generates a namespace for the user with limited capabilities"
    echo "(2) Creates a kubeconfig file based on namespace access"
    echo "(3) Creates network policy for namespace (e.g. deny all inbound calls)"
    echo "(4) Creates resource quotas for namespaces"
    echo "Usage example: "
    echo "./create_acct.sh -o -n mynamespace -c 10 -m 20 -e 50 -s 100 -g 1"
    echo "This will overwrite any old namespaces while creating a quota of: "
    echo "10 vcpu, 20Gi memory, 50Gi ephemeral storage, 100Gi persistent storage, 1 gpu"
    echo "Please specify the following parmaters: "
    echo "-o => (no arguments) overwrite existing namespace"
    echo "-a => (no arguments) creates admin profile (no defaults or quotas)"
    echo "-n => namespace for user"
    echo "-c => vcpu quota for user"
    echo "-m => memory (in Gibibytes) quota for user"
    echo "-e => ephemeral storage (in Gibibytes) quota for user; this is storage typically used by container as it grows"
    echo "-s => storage (in GibiBytes) quota for user; this is storage claimed by persistent volume claims"
    echo "-g => gpu (in integer numbers) quota for a user (defaults to 0)"
}

print_error() {
    echo "----------------------------------------------------------------"
    echo "ERROR"
    echo "----------------------------------------------------------------"
    echo $1
    echo "----------------------------------------------------------------"
    exit 1
}

admin=''
namespace=''
overwrite=false
cpu=''
memory=''
ephemeral=''
storage=''
gpu=0
while getopts "n:haoc:m:e:s:g:" opt; do
    case $opt in
    a)
        admin=true
        ;;
    c)
        cpu=$OPTARG
        ;;
    m)
        memory=$OPTARG
        ;;
    e)
        ephemeral=$OPTARG
        ;;
    s)
        storage=$OPTARG
        ;;
    g)
        gpu=$OPTARG
        ;;
    n)
        namespace=$OPTARG
        ;;
    o)  
        overwrite=true
        ;;
    h)
        echo "Help Menu: "
        print_usage
        exit 0
        ;;
    \?)
        echo "Invalid option: -$OPTARG" >&2
        print_usage
        exit 1
        ;;
    :)
        echo "Option -$OPTARG requires an argument." >&2
        print_usage
        exit 1
        ;;
    esac
done

if [ -z $namespace ] 
then
    print_error "Must specify -n to create namespace!"
fi

if [ -z $admin ]
then 
    if [ -z $cpu ] 
    then
        print_error "Must specify -c for vcpu quota!"
    fi  

    if [ -z $memory ] 
    then
        print_error "Must specify -m for memory (Gibibyte) quota!"
    fi

    if [ -z $ephemeral ] 
    then
        print_error "Must specify -e for ephemeral storage (Gibibyte) quota!"
    fi 

    if [ -z $storage ] 
    then
        print_error "Must specify -e for number of storage (Gibibyte)!"
    fi 
fi 

kubectl get ns --all-namespaces | grep -i $namespace > /dev/null
if [ $? -eq 0 ]
then
    if [ "$overwrite" = true ] 
    then
        kubectl delete ns $namespace
    else
        echo "Namespace already exists! Do you want to delete this?"
        while true
        do
            read -p "Do you wish to delete the existing namespace [y/n]?" yn
            case $yn in
                [Yy]* ) kubectl delete ns $namespace; break;;
                [Nn]* ) exit;;
                * ) echo "Please answer yes or no.";;
            esac
        done
    fi
fi 

echo "Applying following parameters: "
echo "Namespace: $namespace"
echo "CPU Quota: $cpu"
echo "Memory Quota: $memory"
echo "Ephemeral Storage Quota: $ephemeral"
echo "Storage Quota: $storage"
echo "GPU Quota: $gpu"

kubectl get clusterrole "$namespace"-user 2>/dev/null
if [ $? -eq 0 ]
then
    kubectl delete clusterrole "$namespace"-user 
fi

kubectl get clusterrolebinding "$namespace"-user-view 2>/dev/null
if [ $? -eq 0 ]
then
    kubectl delete clusterrolebinding "$namespace"-user-view
fi

# Step 1: Create namespace based on template
namespace_template='namespace'
if ! [ -z $admin ]
then
    namespace_template="$namespace_template"-admin
fi
kubectl create ns $namespace
cat << EOF | kubectl apply -f -
$(sed "s/\${namespace}/$namespace/g" ./templates/"$namespace_template".yaml)
EOF

# Step 2: Create config file from token
token_name=$(kubectl get secrets --no-headers -n $namespace -o custom-columns=":metadata.name" | grep -i "$namespace"-tenant)
if [ -z $token_name ]
then
    print_error "token is missing"
fi
echo "$token_name found!"
token=$(kubectl get secret $token_name -n $namespace -o "jsonpath={.data.token}" | base64 --decode)
cert=$(kubectl get secret $token_name -n $namespace -o "jsonpath={.data['ca\.crt']}")
apiserver=$(kubectl config view --minify | grep server | cut -f 2- -d ":" | tr -d " ")
sed "s/\${namespace}/$namespace/g;s/\${certificate}/$cert/g;s/\${token}/$token/g;s,\${apiserver},$apiserver,g;" ./templates/config > "$namespace"_config

# Step 3: Create network policies
cat << EOF | kubectl apply -f -
$(sed "s/\${namespace}/$namespace/g" ./templates/networkpolicy.yaml)
EOF

if ! [ -z $admin ]
then
    exit
fi

# Step 4: Create default resources
cat << EOF | kubectl apply -f -
$(sed "s/\${namespace}/$namespace/g" ./templates/defaults.yaml)
EOF

# Step 5: Create quotas
cat << EOF | kubectl apply -f -
$(sed "s/\${namespace}/$namespace/g;s/\${cpu}/$cpu/g;s/\${memory}/$memory/g;s/\${storage}/$storage/g;s/\${ephemeral}/$ephemeral/g;s/\${gpu}/$gpu/g;" ./templates/quota.yaml)
EOF