# Kube Tenancy

**Script (create_acct.sh) performs the following:**
1. Generates a namespace for the user with limited capabilities
2. Creates a kubeconfig file based on namespace access
3. Creates network policy for namespace (e.g. deny all inbound calls)
4. Creates resource quotas for namespaces

**Usage example:**
- echo ./create_acct.sh -o -n mynamespace -c 10 -m 20 -e 50 -s 100 -g 1

This will overwrite any old namespaces while creating a quota of: 
*10 vcpu, 20Gi memory, 50Gi ephemeral storage, 100Gi persistent storage, 1 gpu*

List of parameters for the script:
- o => (no arguments) overwrites existing namespace; if namespace exists, you will be prompted otherwise
- a => (no arguments) creates admin profile ; no quotas or defaults
- n => namespace for user
- c => vcpu quota for user
- m => memory (in Gibibytes) quota for user
- e => ephemeral storage (in Gibibytes) quota for user; this is storage typically used by container as it grows
- s => storage (in GibiBytes) quota for user; this is storage claimed by persistent volume claims
- g => gpu (in integer numbers) quota for a user (defaults to 0)

**Removing Tenant**

Simply delete the namespace that you created for the tenant => kubectl delete ns <namespace>
