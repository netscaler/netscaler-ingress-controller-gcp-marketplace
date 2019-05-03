
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
gcloud beta container --project "some-example-project" clusters create "citrix-cic" --zone "asia-south1-a" --username "admin" --cluster-version "1.11.8-gke.6" --machine-type "n1-standard-2" --image-type "COS" --disk-type "pd-standard" --disk-size "100"  --num-nodes "3" --network "projects/some-example-project/global/networks/k8s-server" --subnetwork "projects/some-example-project/regions/asia-south1/subnetworks/k8s-server-subnet" --addons HorizontalPodAutoscaling,HttpLoadBalancing
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
gcloud compute --project=some-example-project instances create vpx-frontend-ingress --zone=asia-south1-a --machine-type=n1-standard-4 --network-interface subnet=k8s-mgmt-subnet --network-interface subnet=k8s-server-subnet --network-interface subnet=k8s-client-subnet --image=vpx-gcp-12-1-51-16 --image-project=some-example-project --boot-disk-size=20GB
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
Now the VPX instance is ready

#### Clone this repo
Clone this repo and the associated tools repo:
```shell
git clone --recursive https://github.com/GoogleCloudPlatform/click-to-deploy.git
```

#### Install the Application resource definition
An Application resource is a collection of individual Kubernetes components,
such as Services, Deployments, and so on, that you can manage as a group.

To set up your cluster to understand Application resources, run the following
command:
```shell
kubectl apply -f "https://raw.githubusercontent.com/GoogleCloudPlatform/marketplace-k8s-app-tools/master/crd/app-crd.yaml"
```

You need to run this command once.

The Application resource is defined by the [Kubernetes SIG-apps](https://github.com/kubernetes/community/tree/master/sig-apps) community. The source code can be found on [github.com/kubernetes-sigs/application](https://github.com/kubernetes-sigs/application).


### **Install the Application**

Go to GoogleCloudPlatform/click-to-deploy/k8s folder and clone this repo. Go to citrix-ingress-controller-gcp-marketplace directory:
```shell
cd click-to-deploy/k8s
git clone https://github.com/citrix/citrix-ingress-controller-gcp-marketplace.git
cd citrix-ingress-controller-gcp-marketplace/

```

The following table lists the configurable parameters of the Citrix Ingress Controller chart and their default values.

| Parameter |    Description | Default |
| --------- |  ---------------- | ------- |
|```license.accept```|Set to accept to accept the terms of the Citrix license|```no```|
|``` cic.image ``` | Image Repository|```quay.io/citrix/citrix-k8s-ingress-controller:1.1.1```|
|``` cic.pullPolicy```| CIC Image Pull Policy  |```Always```|
|```loginFileName```| Secret keys for login into NetScaler VPX or MPX Refer Secret Keys |```nslogin```|
|```nsIP```|NetScaler VPX/MPX IP|```x.x.x.x```|
|```nsPort```|Optional:This port is used by Citrix Ingress Controller to communicate with NetScaler. Can use 80 for HTTP |```443```|
|```nsProtocol```|Optional:This protocol is used by Citrix Ingress Controller to communicate with NetScaler. Can use HTTP with nsPort as 80|```HTTPS```|
|```logLevel```|Optional: This is used for controlling the logs generated from Citrix Ingress Controller. options available are CRITICAL ERROR WARNING INFO DEBUG |```DEBUG```|
|```ingressClass```| Name of Ingress Classes |```nil```|
|```nodeWatch```| Use for automatic route configuration on NetScaler towards the pod network |```false```|
|```exporter.required```|Exporter to be run as sidecar with CIC|```false```|
|```exporter.image```|Exporter image repository|```quay.io/citrix/netscaler-metrics-exporter:v1.0.4```|
|```exporter.pullPolicy```|Exporter Image Pull Policy|```Always```|
|```exporter.ports.containerPort```|Exporter Container Port|```8888```|

Assign values to the required parameters: 

* NS_IP should be replaced with the NSIP or SNIP with management access enabled of the VPX instance. In my example it is "172.18.0.5"
* NS_VIP should be replaced with the VIP (Client side IP) of the VPX instance. In my example it is "172.19.0.2"

```shell
NSIP=<NSIP-of-VPX-instance or SNIP-with-management-access-enabled>
NSVIP=<VIP-of-VPX-instance>
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
helm template chart/citrix-k8s-ingress-controller \
  --name $CITRIX_NAME \
  --namespace $CITRIX_NAMESPACE \
  --set license.accept=yes \
  --set serviceAccount=$CITRIX_SERVICEACCOUNT \
  --set nsIP=$NSIP \
  --set nsVIP=$NSVIP > /tmp/$CITRIX_NAME.yaml
```

Finally, deploy the chart:
```shell
kubectl create -f /tmp/$CITRIX_NAME.yaml
```

#### **Uninstall the Application**
Delete the application, service account and cluster:
```shell
kubectl delete -f /tmp/$CITRIX_NAME.yaml
cat service_account.yaml | sed -e "s/{NAMESPACE}/$CITRIX_NAMESPACE/g" -e "s/{SERVICEACCOUNTNAME}/$CITRIX_SERVICEACCOUNT/g" | kubectl delete -f -
gcloud container clusters delete citrix-cic --zone asia-south1-a
```

# **Code of Conduct**
This project adheres to the [Kubernetes Community Code of Conduct](https://github.com/kubernetes/community/blob/master/code-of-conduct.md). By participating in this project you agree to abide by its terms.
## For More Info, please visit: https://github.com/citrix/citrix-k8s-ingress-controller
