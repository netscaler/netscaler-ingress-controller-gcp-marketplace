# **Description**

This repository contains the Citrix NetScaler Ingress Controller built around  [Kubernetes Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/). This controller automatically configures one or more Citrix NetScaler ADC based on Ingress resource configuration .
Learn more about using Ingress on [k8s.io](https://kubernetes.io/docs/concepts/services-networking/ingress/) 

# **What is an Ingress Controller?**

An Ingress Controller is a controller that watches the Kubernetes API server for updates to the Ingress resource and reconfigures the Ingress load balancer accordingly.

The Citrix Ingress Controller can be deployed on GKE by using helm charts.

# **Citrix Ingress Controller Features**

Features supported by Citrix Ingress Controller can be found [here](https://github.com/citrix/citrix-k8s-ingress-controller/tree/master/deployment#citrix-ingress-controller-features)

# **Installation**
## **Command line instructions**
You can use [Google Cloud Shell](https://cloud.google.com/shell/) or a local
workstation to complete these steps.

[![Open in Cloud Shell](http://gstatic.com/cloudssh/images/open-btn.svg)](https://console.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/GoogleCloudPlatform/click-to-deploy&cloudshell_working_dir=k8s/jenkins)

### Prerequisites
#### Set up command-line tools
You'll need the following tools in your development environment. If you are using Cloud Shell, gcloud, kubectl, Docker, and Git are installed in your environment by default.

* [gcloud](https://cloud.google.com/sdk/gcloud/)
* [kubectl](https://kubernetes.io/docs/reference/kubectl/overview/)
* [docker](https://docs.docker.com/install/)
* [git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
* [helm](https://helm.sh)

Configure `gcloud` as a Docker credential helper:

```shell
gcloud auth configure-docker
```

#### Create 3 VPC networks, subnets and respective firewall rules

**Create a VPC for Management traffic**
```
gcloud compute --project=some-example-project networks create k8s-mgmt --subnet-mode=custom
gcloud compute --project=some-example-project networks subnets create k8s-mgmt-subnet --network=k8s-mgmt --region=asia-south1 --range=172.17.0.0/16
gcloud compute firewall-rules create k8s-allow-mgmt --network k8s-mgmt --allow tcp:443,tcp:80,tcp:22
```

**Create a VPC for Server side or Private communication with the Kubernetes cluster**
```
gcloud compute --project=some-example-project networks create k8s-server --subnet-mode=custom
gcloud compute --project=some-example-project networks subnets create k8s-server-subnet --network=k8s-server --region=asia-south1 --range=172.18.0.0/16
gcloud compute firewall-rules create k8s-allow-server --network k8s-server --allow tcp:443,tcp:80
```

**Create a VPC for Client traffic**
```
gcloud compute --project=some-example-project networks create k8s-client --subnet-mode=custom
gcloud compute --project=some-example-project networks subnets create k8s-client-subnet --network=k8s-client --region=asia-south1 --range=172.19.0.0/16
gcloud compute firewall-rules create k8s-allow-client --network k8s-client --allow tcp:443,tcp:80
```

#### Create a 3 node GKE cluster

```
gcloud beta container --project "some-example-project" clusters create "citrix-cic" --zone "asia-south1-a" --cluster-version "1.22.11-gke.400" --machine-type "n1-standard-2" --image-type "COS" --disk-type "pd-standard" --disk-size "100"  --num-nodes "3" --network "projects/some-example-project/global/networks/k8s-server" --subnetwork "projects/some-example-project/regions/asia-south1/subnetworks/k8s-server-subnet" --addons HorizontalPodAutoscaling,HttpLoadBalancing
```

Connect to the created Kubernetes cluster and create a cluster-admin role for your Google Account

```
gcloud container clusters get-credentials citrix-cic --zone asia-south1-a --project some-example-project 
```
Now your kubectl client is updated with the credentials required to login to the newly created Kubernetes cluster

```
kubectl create clusterrolebinding cpx-cluster-admin --clusterrole=cluster-admin --user=<email of the gcp account>
```

#### Deploying a Citrix ADC VPX instance on Google Cloud

Follow the guide [Deploy a Citrix ADC VPX instance on Google Cloud Platform](https://docs.citrix.com/en-us/citrix-adc/12-1/deploying-vpx/deploy-vpx-google-cloud.html) to download the VPX from Citrix Downloads, uploading to Google Cloud's storage and to create a Citrix ADC VPX image out of it.

**Create a VPX instance (assuming you have already created the VPX image)**
```
gcloud compute --project=some-example-project instances create vpx-frontend-ingress --zone=asia-south1-a --machine-type=n1-standard-4 --network-interface subnet=k8s-mgmt-subnet --network-interface subnet=k8s-server-subnet --network-interface subnet=k8s-client-subnet --image=<image-name> --image-project=some-example-project --boot-disk-size=20GB
```

**IMPORTANT**
After executing the above command, it would return both the private IPs and the Public IPs of the newly created VPX instance. Make a note of it.

**Example:**

```
# gcloud compute --project=some-example-project instances create vpx-frontend-ingress --zone=asia-south1-a --machine-type=n1-standard-4 --network-interface subnet=k8s-mgmt-subnet --network-interface subnet=k8s-server-subnet --network-interface subnet=k8s-client-subnet --image=vpx-gcp-12-1-51-16 --image-project=some-example-project --boot-disk-size=20GB
Created [https://www.googleapis.com/compute/v1/projects/some-example-project/zones/asia-south1-a/instances/vpx-frontend-ingress].
NAME                  ZONE           MACHINE_TYPE   PREEMPTIBLE  INTERNAL_IP                       EXTERNAL_IP                   STATUS
vpx-frontend-ingress  asia-south1-a  n1-standard-4               172.17.0.2,172.18.0.5,172.19.0.2  1.1.1.1,1.1.1.2,1.1.1.3       RUNNING
```

Explanation of the IP address captured from previous output:

| Private IP |    Public IP   |   Network  |              Comments             |
|:----------:|:--------------:|:----------:|:---------------------------------:|
| 172.17.0.2 | 1.1.1.1        | Management | NSIP                              |
| 172.18.0.5 | 1.1.1.2        | Server     | SNIP (to communicate with K8s)    |
| 172.19.0.2 | 1.1.1.3        | Client     | VIP (to receive incoming traffic) |

**NOTE** The external IPs has been replaced to dummy IPs for obvious reasons.

#### Basic configurtion of VPX

Login to the newly created VPX instance and do some basic configs

```
ssh nsroot@1.1.1.1
<input the password>

clear config -force full
add ns ip 172.18.0.5 255.255.0.0 -type snip -mgmt enabled
enable ns mode MBF
```
Now the VPX instance is ready.

#### Clone this repo
Clone this repo. Go to citrix-ingress-controller-gcp-marketplace directory:
```shell
git clone https://github.com/citrix/citrix-ingress-controller-gcp-marketplace.git
cd citrix-ingress-controller-gcp-marketplace/
```

#### Install the Application resource definition
An Application resource is a collection of individual Kubernetes components,
such as Services, Deployments, and so on, that you can manage as a group.

To set up your cluster to understand Application resources, run the following
command:
```shell
make crd/install
```

You need to run this command once.

The Application resource is defined by the [Kubernetes SIG-apps](https://github.com/kubernetes/community/tree/master/sig-apps) community. The source code can be found on [github.com/kubernetes-sigs/application](https://github.com/kubernetes-sigs/application).


### **Install the Application**

The following table lists the configurable parameters of the Citrix Ingress Controller chart and their default values.

| Parameters | Mandatory or Optional | Default value | Description |
| --------- | --------------------- | ------------- | ----------- |
| license.accept | Mandatory | no | Set `yes` to accept the CIC end user license agreement. |
| nsIP | Mandatory | N/A | The IP address of the Citrix ADC device. For details, see [Prerequisites](#prerequistes). |
| nsVIP | Optional | N/A | The Virtual IP address on the Citrix ADC device. |
| nsSNIPS | Optional | N/A | The subnet IPAddress on the Citrix ADC device, which will be used to create PBR Routes instead of Static Routes [PBR support](https://github.com/citrix/citrix-k8s-ingress-controller/tree/master/docs/how-to/pbr.md) |
| adcCredentialSecret | Mandatory | N/A | The secret key to log on to the Citrix ADC VPX or MPX. For information on how to create the secret keys, see [Prerequisites](#prerequistes). |
| nsPort | Optional | 443 | The port used by CIC to communicate with Citrix ADC. You can use port 80 for HTTP. |
| nsProtocol | Optional | HTTPS | The protocol used by CIC to communicate with Citrix ADC. You can also use HTTP on port 80. |
| logLevel | Optional | DEBUG | The loglevel to control the logs generated by CIC. The supported loglevels are: CRITICAL, ERROR, WARNING, INFO, DEBUG and TRACE. For more information, see [Logging](https://github.com/citrix/citrix-k8s-ingress-controller/blob/master/docs/configure/log-levels.md).|
| entityPrefix | Optional | k8s | The prefix for the resources on the Citrix ADC VPX/MPX. |
| jsonLog | Optional | false | Set this argument to true if log messages are required in JSON format |
| nitroReadTimeout | Optional | 20 | The nitro Read timeout in seconds, defaults to 20 |
| clusterName | Optional | N/A | The unique identifier of the kubernetes cluster on which the CIC is deployed. Used in multi-cluster deployments. |
| kubernetesURL | Optional | N/A | The kube-apiserver url that CIC uses to register the events. If the value is not specified, CIC uses the [internal kube-apiserver IP address](https://kubernetes.io/docs/tasks/access-application-cluster/access-cluster/#accessing-the-api-from-a-pod). |
| ingressClass | Optional | N/A | If multiple ingress load balancers are used to load balance different ingress resources. You can use this parameter to specify CIC to configure Citrix ADC associated with specific ingress class. For more information on Ingress class, see [Ingress class support](https://developer-docs.citrix.com/projects/citrix-k8s-ingress-controller/en/latest/configure/ingress-classes/). For Kubernetes version >= 1.19, this will create an IngressClass object with the name specified here |
| setAsDefaultIngressClass | Optional | False | Set the IngressClass object as default ingress class. New Ingresses without an "ingressClassName" field specified will be assigned the class specified in ingressClass. Applicable only for kubernetes versions >= 1.19 |
| updateIngressStatus | Optional | False | Set this argurment if `Status.LoadBalancer.Ingress` field of the Ingress resources managed by the Citrix ingress controller needs to be updated with allocated IP addresses. For more information see [this](https://github.com/citrix/citrix-k8s-ingress-controller/blob/master/docs/configure/ingress-classes.md#updating-the-ingress-status-for-the-ingress-resources-with-the-specified-ip-address). |
| serviceClass | Optional | N/A | By Default ingress controller configures all TypeLB Service on the ADC. You can use this parameter to finetune this behavior by specifing CIC to only configure TypeLB Service with specific service class. For more information on Service class, see [Service class support](https://developer-docs.citrix.com/projects/citrix-k8s-ingress-controller/en/latest/configure/service-classes/). |
| defaultSSLCertSecret | Optional | N/A | Provide Kubernetes secret name that needs to be used as a default non-SNI certificate in Citrix ADC. |
| podIPsforServiceGroupMembers | Optional | False |  By default Citrix Ingress Controller will add NodeIP and NodePort as service group members while configuring type LoadBalancer Services and NodePort services. This variable if set to `True` will change the behaviour to add pod IP and Pod port instead of nodeIP and nodePort. Users can set this to `True` if there is a route between ADC and K8s clusters internal pods either using feature-node-watch argument or using Citrix Node Controller. |
| ignoreNodeExternalIP | Optional | False | While adding NodeIP, as Service group members for type LoadBalancer services or NodePort services, Citrix Ingress Controller has a selection criteria whereas it choose Node ExternalIP if available and Node InternalIP, if Node ExternalIP is not present. But some users may want to use Node InternalIP over Node ExternalIP even if Node ExternalIP is present. If this variable is set to `True`, then it prioritises the Node Internal IP to be used for service group members even if node ExternalIP is present |
| disableAPIServerCertVerify | Optional | False | Set this parameter to True for disabling API Server certificate verification. |
| ipam | Optional | False | Set this argument if you want to use the IPAM controller to automatically allocate an IP address to the service of type LoadBalancer. |
| nodeWatch | Optional | false | Use the argument if you want to automatically configure network route from the Ingress Citrix ADC VPX or MPX to the pods in the Kubernetes cluster. For more information, see [Automatically configure route on the Citrix ADC instance](https://developer-docs.citrix.com/projects/citrix-k8s-ingress-controller/en/latest/network/staticrouting/#automatically-configure-route-on-the-citrix-adc-instance). |
| nodeSelector.key | Optional | N/A | Node label key to be used for nodeSelector option in CIC deployment. |
| nodeSelector.value | Optional | N/A | Node label value to be used for nodeSelector option in CIC deployment. |
| nsHTTP2ServerSide | Optional | OFF | Set this argument to `ON` for enabling HTTP2 for Citrix ADC service group configurations. |
| nsCookieVersion | Optional | 0 | Specify the persistence cookie version (0 or 1). |
| nsConfigDnsRec | Optional | false | To enable/disable DNS address Record addition in ADC through Ingress |
| nsSvcLbDnsRec | Optional | false | To enable/disable DNS address Record addition in ADC through Type Load Balancer Service |
| nsDnsNameserver | Optional | N/A | To add DNS Nameservers in ADC |
| exporter.required | Optional | false | Use the argument, if you want to run the [Exporter for Citrix ADC Stats](https://github.com/citrix/citrix-adc-metrics-exporter) along with CIC to pull metrics for the Citrix ADC VPX or MPX|
| exporter.pullPolicy | Optional | IfNotPresent | The Exporter image pull policy. |
| exporter.ports.containerPort | Optional | 8888 | The Exporter container port. |
| crds.install | Optional | False | Unset this argument if you don't want to install CustomResourceDefinitions which are consumed by CIC. |
| crds.retainOnDelete | Optional | false | Set this argument if you want to retain CustomResourceDefinitions even after uninstalling CIC. This will avoid data-loss of Custom Resource Objects created before uninstallation. |
| coeConfig.required | Mandatory | false | Set this to true if you want to configure Citrix ADC to send metrics and transaction records to COE. |
| coeConfig.distributedTracing.enable | Optional | false | Set this value to true to enable OpenTracing in Citrix ADC. |
| coeConfig.distributedTracing.samplingrate | Optional | 100 | Specifies the OpenTracing sampling rate in percentage. |
| coeConfig.endpoint.server | Optional | N/A | Set this value as the IP address or DNS address of the  analytics server. |
| analyticsConfig.endpoint.service | Optional | N/A | Set this value as the IP address or service name with namespace of the analytics service deployed in k8s environment. Format: namespace/servicename |
| coeConfig.timeseries.port | Optional | 30002 | Specify the port used to expose COE service outside cluster for timeseries endpoint. |
| coeConfig.timeseries.metrics.enable | Optional | False | Set this value to true to enable sending metrics from Citrix ADC. |
| coeConfig.timeseries.metrics.mode | Optional | avro |  Specifies the mode of metric endpoint. |
| coeConfig.timeseries.auditlogs.enable | Optional | false | Set this value to true to export audit log data from Citrix ADC. |
| coeConfig.timeseries.events.enable | Optional | false | Set this value to true to export events from the Citrix ADC. |
| coeConfig.transactions.enable | Optional | false | Set this value to true to export transactions from Citrix ADC. |
| coeConfig.transactions.port | Optional | 30001 | Specify the port used to expose COE service outside cluster for transaction endpoint. |
| nsLbHashAlgo.required | Optional | false | Set this value to set the LB consistent hashing Algorithm |
| nsLbHashAlgo.hashFingers | Optional | 256 | Specifies the number of fingers to be used for hashing algorithm. Possible values are from 1 to 1024, Default value is 256 |
| nsLbHashAlgo.hashAlgorithm | Optional | 'default' | Specifies the supported algorithm. Supported algorithms are "default", "jarh", "prac", Default value is 'default' |

Assign values to the required parameters: 

* NSIP should be replaced with the NSIP or SNIP with management access enabled of the VPX instance. In my example it is "172.18.0.5"
* The user name and password of the Citrix ADC VPX or MPX appliance used as the ingress device. The Citrix ADC appliance needs to have system user account (non-default) with certain privileges so that Citrix ingress controller can configure the Citrix ADC VPX or MPX appliance. For instructions to create the system user account on Citrix ADC, see [Create System User Account for CIC in Citrix ADC](#create-system-user-account-for-cic-in-citrix-adc).

  You can pass user name and password using Kubernetes secrets. Create a Kubernetes secret for the user name and password using the following command:

    ```
       kubectl create secret generic nslogin --from-literal=username='cic' --from-literal=password='mypassword'
    ```
  Use this secret name in NSSECRET parameter.

Set the following variables:

```shell
NSIP=<NSIP-of-VPX-instance or SNIP-with-management-access-enabled>
NSSECRET=<Kubenetes-Secret-Name-for-Citrix-ADC-Credentials>
CITRIX_NAME=citrix-1
CITRIX_NAMESPACE=default
CITRIX_SERVICEACCOUNT=cic-k8s-role
```

Create a service account with required permissions:

```shell
cat service_account.yaml | sed -e "s/{NAMESPACE}/$CITRIX_NAMESPACE/g" -e "s/{SERVICEACCOUNTNAME}/$CITRIX_SERVICEACCOUNT/g" | kubectl create -f -
```

> NOTE: The above are the mandatory parameters. In addition to these you can also assign values to the parameters mentioned in the above table.

Create a template for the chart using the parameters you want to set:
```
helm template $CITRIX_NAME chart/citrix-ingress-controller \
  --namespace $CITRIX_NAMESPACE \
  --set license.accept=yes \
  --set serviceAccount=$CITRIX_SERVICEACCOUNT \
  --set nsIP=$NSIP \
  --set adcCredentialSecret=$NSSECRET > /tmp/$CITRIX_NAME.yaml
```

Finally, deploy the chart:
```shell
kubectl create -f /tmp/$CITRIX_NAME.yaml -n $CITRIX_NAMESPACE
```

#### **Uninstall the Application**
Delete the application, service account and cluster:
```shell
kubectl delete -f /tmp/$CITRIX_NAME.yaml -n $CITRIX_NAMESPACE
cat service_account.yaml | sed -e "s/{NAMESPACE}/$CITRIX_NAMESPACE/g" -e "s/{SERVICEACCOUNTNAME}/$CITRIX_SERVICEACCOUNT/g" | kubectl delete -f -
gcloud container clusters delete citrix-cic --zone asia-south1-a
```

# **Code of Conduct**
This project adheres to the [Kubernetes Community Code of Conduct](https://github.com/kubernetes/community/blob/master/code-of-conduct.md). By participating in this project you agree to abide by its terms.
## For More Info, please visit: https://github.com/citrix/citrix-k8s-ingress-controller
