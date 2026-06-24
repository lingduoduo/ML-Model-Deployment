### Kubernetes 

Understanding Kubernetes

- Understanding Kubernetes Core Functions
  - Kubernettes is. an open-source system for automating. deployment, scaling and managing of containerized applications
- Understanding Kubernetes Origins
- Understanding Kubernetes Management interfaces
  - API/REST -> etcd
    - The kubernetes API defines objects in a Kubernetes environment
    - kubectl commands - the kubectl command line utility provides convenient administrator access, allowing us to run many tasks against the cluster
    - dashboard
    - Direct API access using commands, such as curl allows develpers to addresst the cluster using API calls from custom scripts (curl, python code))

EKS is Amazon's implementation of the Kubernetes. Most of the K8S concentps are universal ot any Kubernetes platfrom, unless stated otherwise.

| K8s/EKS | Description                                                  |
| ------- | ------------------------------------------------------------ |
| Image   | Docker image                                                 |
| Pod     | A unit of workload that shares local host, consists of one or more containers |
|  Container    | A instantialtion of Docker image |
|  Sidecar    | An additional container in the pod that performas supporting fucntion (proxu/logging etc) |
|  Service    | An entity you can address that load-balances betwen pods, as opposed to address each pod individually |
|  Horizontal Pod Autoscaler    | Rules to define how many pods to run |
|  Resources: CPU/MEM    | Requests and limits or compute resources |
|  Deployment    | Defines workload, allows rolling updates |
|  Rollout    | Deployedment + advanced canary deployment |
|  ReplicaSet    | Controls number of running pods and groups them. Created by DeploymentRollout |
|  Ingress    | Definition of the inbound "gate" for the traffic into Kubernetes |
|  ConfigMap    | Key-value entry |
|  Secrets    | Opaque ConfigMap |
|  ServiceAccount    | The account that can be granted permissions and attached to a pod. IAM role is possible to be attached in EKS |
|  PodDisruptionBudget    | Assertion on how many pods should run at minimum durign nodes drain/replacement |
|  Istio VirtualService    | Istio-sprcific |
|  ServiceEntry    | Istio-specific. Specifies exteranlservices that are outside the service mesh |

**Kubernetes**

When a microservice application is deployed in production, it usually has many running containers that need to be allocated the right amount of resources in response to user demands. Also, there is a need to ensure that the containers are online, are running, and are communicating with one another. The need to efficiently manage and coordinate clusters of containerized applications gave rise to Kubernetes.

Kubernetes is a software system that addresses the concerns of deploying, scaling, and monitoring containers. Hence, it is called a container orchestrator. Examples of other container orchestrators in the wild are Docker Swarm, Mesos Marathon, and HashiCorp Nomad.

Kubernetes was built and released by Google as an open source software, which is now managed by the Cloud Native Computing Foundation (CNCF) . Google Cloud Platform offers a managed Kubernetes service called Google Kubernetes Engine (GKE). Amazon Elastic Container Service for Kubernetes (EKS) also provides a managed Kubernetes service.

- Kubernetes maintains high availability and fault tolerance through replication, self-healing, and automated scaling.
- A Kubernetes cluster consists of a master node and multiple worker nodes.
- The master node manages the cluster, while worker nodes host containers.
- Key components of the master node include the API Server, Etcd, Controller Manager, and Scheduler.

Pods are the smallest deployable units in Kubernetes - They can contain one or more containers that share the same network namespace.

**Components of Kubernetes**

- Master Node: Controls and manages the cluster. Manages the Kubernetes cluster. There may be more than one master node in high availability mode for fault-tolerance purposes. In this case, only one is the master, and the others follow. 
-  Worker node(s): Worker machine where containers are launched. Machine(s) that runs containerized applications that are scheduled as pod(s).
- Etcd: Consistent and highly-available key-value store.
- Kubelet: Ensures containers are running in a Pod.
- Kube Proxy: Maintains network rules.

### Kubernetes Cluster

- How we can deploy our Machine learning models using this Architecture
- What are the Master and Worker Node Components, How we can use them to deploy our ML Models.
- How we can use YAML files by providing our requirements
- Use cases of kubectl cli to communicate to our cluster
- What is DSC and how we can benefit from that

Gain Insights into Scaling and High Availability

Control Plane's Role: The Control Plane oversees container distribution across nodes, issuing deployment commands and managing container placement.

Developer Interaction: Developers use Kubectl within the Control Plane to command the deployment of containers. They specify details like the number of containers and their types.

YAML Configuration Files: YAML files contain vital application configurations, such as container names, replica numbers, pod details, and service settings (e.g., load balancer configurations). These files guide container deployment.

Kubectl Communication: Developers send YAML files to the Control Plane via Kubectl, enabling seamless communication and ensuring the accurate deployment of containers based on specified configurations.

### Container Deployment Process

Interaction with Kubelet: Deployment involves communication with Kubelet, a key Kubernetes component within nodes.

Request Handling: Kubelet processes commands issued by the Scheduler & Controller Manager, initiating container deployment within specific nodes, such as Node1 with Container-1 & Container-2.

Impact of Node Failure: If a node, like Node 2, crashes, containers on that node (e.g., Container-3) are affected.

Desired State Configuration (DSC): Kubernetes uses Desired State Configuration (DSC) to ensure the desired number of containers (e.g., 5) specified by the developer are consistently running in the cluster, even in the event of node failures.

### Container Recovery Process

Automatic Rescheduling: If a container crashes, Kubernetes initiates automatic rescheduling on other available nodes.

Resource Availability Check: Kubernetes checks available resources, starting with Node-1, and moves to Node-3 if resources are insufficient on the first node.

Ensuring Container Uptime: Kubernetes ensures all containers remain operational by redistributing them across healthy nodes.

### User Access to Applications

Direct Node Access: Users can access applications installed in nodes directly, bypassing the Control Plane.

Load Balancer Implementation: Instead of accessing containers directly, users go through a Load Balancer, which distributes requests across multiple application instances (e.g., Container-4, Container-1, Container-2, Container-3) based on its decisions.

### Key Concepts

Pods:
Pods are high level structure that wrap one or more containers. This is because containers are not run directly in Kubernetes, Containers in the same pod share a local network & the same resources, allowing them to easily communicate with other containers in the same pod as if they are on the same machine while at the same time maintaining a degree of isolation.

Kube-scheduler:
Assigns Nodes to newly created Pods.

NameSpace:
Used for dividing cluster resources between multiple users.
Initial NameSpaces – Default, Kube-system, Kube-public.

Kubelet:
Is a service agent that controls & maintains a set of pods by watching for pod specs through the Kubernetes api server. It preserves the pod life-cycle by ensuring that a given set of containers are all running as they should.
The Kubelet runs on each Node & enables the communication b/w the Master and Slave Nodes.

Kube-proxy:
Is responsible for directing traffic to the right container based on IP and Port Number of Incoming requests.

Kubernetes Master Components
Etcd: The Cluster's Brain
Distributed Key-Value Store for Config Data

API Server: Frontend to the Cluster Control Plane
Validates and Configures Data for API Objects

Controller Manager: Maintaining Desired State
Regulates the State of the System

Scheduler: Assigning Work to Nodes
Selects Nodes for Pods to Run Based on Policies

### Interacting with Kubernetes: Kubectl CLI and YAML Files

Kubectl (Kube Control) is the command-line tool for interacting with Kubernetes clusters.

Key commands: kubectl get, kubectl create, kubectl apply, kubectl delete

YAML (YAML Ain't Markup Language) is used for configuration and resource definition in Kubernetes.

Structure: API version, kind, metadata, spec.

Kubectl provides a powerful interface for managing clusters, allowing both beginners and experts to interact with Kubernetes.

YAML files offer a declarative and version-controlled way to define and manage Kubernetes resources.

Version history and rollback capabilities with YAML files.

Kubectl is the primary command-line interface for interacting with Kubernetes clusters, offering a wide range of functionality for managing resources.

### Basic kubectl command

```
kubectl create deployment [name]
kubectl edit deployment [name]
kubectl delete deployment [name]
```

```
kubectl get node | pod | services | replicaset | deployment
```

```
minikube start

# Run a test container image that includes a webserver
kubectl create deployment hello-node --image=registry.k8s.io/e2e-test-images/agnhost:2.39 -- /agnhost netexec --http-port=8080

kubectl get deployments
kubectl get pods
kubectl get pods -o wide
kubectl get events

kubectl logs hello-node-5f76cf6ccf-br9b5

kubectl expose deployment hello-node --type=LoadBalancer --port=8080

kubectl get services
minikube service hello-node
kubectl get pod,svc -n kube-system
kubectl delete service hello-node
kubectl delete deployment hello-node

minikube stop
```

### Load Balancer in Kubernetes

Ensuring efficient distribution of traffic across pods/nodes.

Improving scalability, reliability, and high availability.

Enhancing fault tolerance: redirecting traffic in case of pod/node failures. 

Configurable parameters and annotations allow fine-tuning of load balancing strategies.

In Kubernetes, Services act as Load Balancers


### Desired State Configuration (DSC) in Kubernetes

Automated Reconciliation in Kubernetes  

Kubernetes continuously monitors the cluster's state.

Kubernetes DSC ensures that the cluster components, applications, and configurations match the defined desired state.

Automatic reconciliation reduces manual intervention, making the cluster self-healing and ensuring high availability.

By defining the desired state, operators can set specific configurations, security policies, and resource limits, ensuring consistency across deployments.

## Kubernetes Deployment

Understanding Replica Sets and Pods.
Creating and managing a basic Deployment.
Scaling applications using Deployments - HPA based on CPU utilization
Performing rolling updates and rollbacks.

- How to define deployments with their Configuration and Specifications
- Creating Deployment configurations using YAML.
- What are the different types of deployments and when to use them.

- Ensuring High Availability and Fault Tolerance: 

Deployments provide an abstraction layer, managing replica sets and pods, ensuring your application is always available even if one or more instances fail.

- Rolling Updates and Rollbacks for Seamless Deployments: 

Deployments allow you to update your application without downtime, ensuring smooth transitions between versions. If issues arise, rollbacks can be executed quickly.

- Zero-Downtime Deployments and Scalability: 

With rolling updates, new versions of your application can be deployed with zero downtime. Additionally, Deployments enable easy scaling, both vertically and horizontally, to handle varying workloads.

- Key Points:

  Deployments in Kubernetes offer crucial features for managing applications, including high availability, seamless updates, rollbacks, and scalability.

  By abstracting the underlying complexity, Deployments simplify the management of applications, allowing focus on functionality and user experience.

  Deployments act as the cornerstone of Kubernetes, providing essential features for managing applications efficiently.

### Creating Kubernetes Deployments: Configuration and Specification

Defining Deployments in YAML: Configuration and Specifications

In Kubernetes, deployments are defined using YAML files, allowing for precise configuration and specifications.

Understanding the YAML Structure: API Version, Kind, Metadata, and Spec

 - API Version: Specifies the Kubernetes API version to use for this object.

 - Kind: Defines the type of Kubernetes object, e.g., Deployment, Service.

 - Metadata: Contains information like name, labels, and annotations.

 - Spec: Specifies the desired state of the Deployment, including pod template and replicas.

## Docker to Kubernetes command mapping

If your model-serving container already works locally with Docker:

```bash
docker run -p 8080:8080 <registry>/<image>:<tag>

curl http://localhost:8080/health

curl -X POST http://localhost:8080/predict \
  -H "Content-Type: application/json" \
  -d '{"user_id":"u1","top_k":5}'
```

then the Kubernetes version in this repo is:

### 1. Deploy the same image with Helm

```bash
helm upgrade --install model-release ./Model-Deployment/chart \
  --namespace model-serving \
  --create-namespace \
  -f ./Model-Deployment/chart/values-staging.yaml \
  --set image.repository=<registry-or-local-image> \
  --set image.tag=<tag> \
  --set container.port=8080 \
  --set service.port=8080
```

### 2. Inspect the deployment

```bash
kubectl get deploy,pods,svc -n model-serving
kubectl describe deployment model-release-model-deployment -n model-serving
kubectl logs -n model-serving deploy/model-release-model-deployment
```

### 3. Access it locally with kubectl

```bash
kubectl port-forward -n model-serving svc/model-release-model-deployment 8080:8080
```

### 4. Reuse the same curl commands

```bash
curl http://localhost:8080/health

curl -X POST http://localhost:8080/predict \
  -H "Content-Type: application/json" \
  -d '{"user_id":"u1","top_k":5}'
```

### 5. Helpful command translation

- `docker run -p 8080:8080 ...` -> `helm upgrade --install ...` + `kubectl port-forward`
- `docker logs <container>` -> `kubectl logs -n model-serving deploy/model-release-model-deployment`
- `docker exec -it <container> sh` -> `kubectl exec -it -n model-serving deploy/model-release-model-deployment -- sh`

### 6. About load balancing

Recommended default in this repo:

- `Deployment` runs multiple replicas
- `Service` with `type: ClusterIP` load-balances traffic across healthy pods
- `Ingress` is used when you need external access, TLS, canary routing, or shadow routing

For local testing, `kubectl port-forward` is the closest equivalent to `docker run -p`.

## Raw manifest first test

If you want to test Kubernetes first before using Helm, use these raw manifests:

- [local-model-deployment.yaml](/Users/linghuang/Git/Model-Deployment/Kubernetes/local-model-deployment.yaml)
- [local-model-service.yaml](/Users/linghuang/Git/Model-Deployment/Kubernetes/local-model-service.yaml)

They assume:

- image: `ling-mlops-sandbox:latest`
- container port: `8080`
- health endpoint: `/health`
- local cluster image access, so `imagePullPolicy: Never`

### Local test steps

1. Make sure the image exists in your local cluster runtime.

For Minikube, the most reliable way is:

```bash
eval $(minikube -p minikube docker-env)
cd /Users/linghuang/Git/Recommendation/TFRecommenders-MLops-Sandbox
docker build -t ling-mlops-sandbox:latest .
docker image ls | grep ling-mlops-sandbox
```

2. Apply the raw manifests:

```bash
kubectl apply -f /Users/linghuang/Git/Model-Deployment/Kubernetes/local-model-deployment.yaml
kubectl apply -f /Users/linghuang/Git/Model-Deployment/Kubernetes/local-model-service.yaml
```

3. Check the workload:

```bash
kubectl get deploy,pods,svc
kubectl describe deployment local-model-deployment
kubectl logs deploy/local-model-deployment
```

4. Port-forward the service:

```bash
kubectl port-forward svc/local-model-service 8080:8080
```

5. Reuse the same curl commands:

```bash
curl http://localhost:8080/health

curl -X POST http://localhost:8080/predict \
  -H "Content-Type: application/json" \
  -d '{"user_id":"u1","top_k":5}'
```

6. Clean up when done:

```bash
kubectl delete -f /Users/linghuang/Git/Model-Deployment/Kubernetes/local-model-service.yaml
kubectl delete -f /Users/linghuang/Git/Model-Deployment/Kubernetes/local-model-deployment.yaml
```


```
minikube start

kubectl run nginx --image=nginx
kubectl describe pod nginx
kubectl run redis --image=redis123 --dry-run -o yaml
kubectl run redis --image=redis123 --dry-run=client -o yaml > redis-pod.yaml

kubectl create -f redis-pod.yaml
kubectl create -f redis-service.yaml
kubectl get pods, svc

kubectl create -f postgres-pod.yaml
kubectl create -f postfres-service.yaml
kubectl get pods, svc

kubectl create -f worker-app-pod.yaml
kubectl create -f worker-app-service.yaml
kubectl get pods, svc

minikube service voting-service --url
minikube service result-service --url
```

To apply this Deployment, save the YAML content to a file (e.g.,nginx-deployment.yaml) and use the kubectl apply command: 

```
kubectl apply -f nginx-deployment.yaml

# Use Yaml to create pods

kubectl create -f redis-pod.yaml
kubectl apply -f redis-pod.yaml
kubectl create -f rc-definition.yaml
kubectl create -f replicaset-definition.yaml
```

Deployment

kind: Deployment

metadata - name, labesl
spec - template, replica, selectors

```
kubectl create -f deployment.yml
kubectl get deployments
kubectl get replicaset
kubectl get pods
kubectl describe deploymnent myapp-deployment
kubectl get all
kubectl get pods, svc
```

```
kubectl create deployment httpd-frontend --image=httpd:2.4-alpine --replicas=3 
kubectl get deployments
kubectl get rs 
kubectl get pods
kubectl describe pod frontend-deployment-name-... 
```
### Replica Sets and Labels: Specifying Desired Replica Count and Identifying Pods


Replica Sets: Ensure the desired number of pod replicas are running at any given time.

Labels: Identifiers used to select and manage subsets of pods.


```
kubectl replace -f replicaset-definition.yaml
kubectl scale --replicas=6 -f replicaset-definition.yaml
kubectl scale --replicas=6 relicaset myapp-replicaset
kubectl get relicaset 
kubectl describe replicaset new-replica-set
```

### Selectors and Templates: Defining Pod Templates with Containers, Ports, and Volumes

Selectors: Criteria used to identify which pods belong to a Replica Set.

Templates: Define pod specifications, including containers, ports, and storage volumes.


### Pod Templates and Stateful vs. Stateless Deployments

Pod Templates

In Kubernetes, a pod template is a blueprint used to create pods. It defines the configuration of containers within the pod, including the Docker image to use, resources like CPU and memory limits, and environment variables. Pod templates also specify how data is stored through volumes, allowing for various types of storage, such as temporary or persistent data. Additionally, ports are mapped within pod templates, allowing communication between containers inside the pod and with external services.

Pod Templates: Specifying Containers, Volumes, and Ports:

  Containers: Defining the application containers, specifying the image, resources, and environment variables.

  Volumes: Configuring data storage, defining the type (emptyDir, hostPath, persistentVolumeClaim, etc.).

  Ports: Mapping container ports to host ports, allowing external access.


### Stateful and Stateless Deployments: Differences and Use Cases

Stateful Deployments: Applications that require stable network identities, persistent storage, and ordered deployment.

Use Cases: Databases, key-value stores, applications relying on unique network identifiers.

Stateless Deployments: Applications where each instance is independent and can handle requests without relying on previous states.

Use Cases: Web servers, microservices, stateless APIs.

### Scaling and Rolling Updates

Deployments enable horizontal scaling to handle varying workloads and vertical scaling for optimizing resource utilization.

Rolling updates ensure seamless transitions between application versions, maintaining high availability.

Rollbacks provide a safety net, allowing quick reverting to previous versions in case of deployment issues.

Recreate vs Rolling Update

```
kubectl create -f deployment.yaml --record
kubectl rollout status deployment.apps/myapp-deployment
kubectl rollout history deployment.apps/myapp-deployment

kubectl describe deployment.apps/myapp-deployment
kubectl edit deployment myapp-deployment --record
kubectl set image deployment  myapp-deployment nginx:1.18-perl --record

kubectl rollout undo deployment.apps/myapp-deployment
kubectl set image daployment frontend simple-web=kodekloud/web-color:v2
```

### Deployment Security

  Role-Based Access Control (RBAC) in Deployments.
  Secrets Management: Safeguarding Sensitive Information.
  Network Policies: Controlling Communication Between Pods.
  Runtime Security: Scanning Containers for Vulnerabilities.


### Best Practices for Kubernetes Deployments

  Labels and Selectors: Effective Use in Deployments.
  Resource Requests and Limits: Optimizing Resource Utilization.
  Monitoring and Logging: Ensuring Health and Performance.
  Security Policies: Protecting Deployed Applications.


## Kubernetes Service

Services ensure reliable communication between different parts of an application, abstracting network complexities.
Different service types cater to specific use cases, balancing internal and external accessibility.
Ingress Controllers enhance routing capabilities, allowing for sophisticated HTTP-based traffic management.


- How to manage network communication in kubernetes
- What are the different types of Services and when we can use these services
- How we can distribute incoming traffic to multiple containers on the basis of IP and ports.
- What are the ingress rules and why we need to use

Service YAML files - how to write our requirements through this file

Understanding the Need for Kubernetes Services

In the dynamic world of Kubernetes, where applications are distributed across multiple pods and nodes, managing network communication efficiently becomes paramount. This is where Kubernetes Services step in to address several critical challenges:

Kubernetes Services: Managing Network Communication

Kubernetes Services play a crucial role in managing network communication within a cluster, allowing different parts of an application to communicate with each other seamlessly. They abstract the underlying network infrastructure, providing a consistent way to expose and access applications, ensuring reliability and flexibility in a dynamic environment.

Pod Abstraction:

Kubernetes Services provide a stable endpoint, abstracting the underlying pods.
Pods in a cluster often have a lifecycle, and their IPs can change due to scaling, failures, or rescheduling. Services offer a consistent way to access applications regardless of pod churn.

Service Discovery:

Services act as a well-known entry point for applications.
This simplifies service discovery for both internal and external components, enabling seamless communication without hardcoding IP addresses.

External Connectivity:

Kubernetes Services enable external access to applications.
By defining appropriate service types (NodePort, LoadBalancer), applications can serve traffic from outside the cluster, making them accessible to users or clients.

Failure Resilience:

Services enhance fault tolerance and high availability.
If a pod or node fails, Services redirect traffic to healthy pods, ensuring that applications remain operational even in the face of failures.

Types of Kubernetes Services

- ClusterIP  ➜ Internal load balancing.
- NodePort ➜ Expose a port on every node.
- LoadBalancer ➜ Balance across nodes, integrated with Cloud provider.
- Ingress Controller ➜ Control at the HTTP(s) application layer.
- ExternalName* ➜ Reversed: network traffic out of the cluster.


Differentiating Types of Services:

NodePort:

Exposes the service on each node's IP at a static port.
Accessible externally using <NodeIP>:<NodePort>.
Useful for accessing services from outside the cluster during development.

ClusterIP:

Internal-only service accessible within the cluster.
Ideal for inter-pod communication.
Not accessible from outside the cluster.

LoadBalancer:

Provisions an external load balancer in the cloud provider's network.
Automatically assigns an external IP to the service.
Balances traffic across multiple nodes, ensuring high availability.

ExternalName:

Maps the service to the contents of the externalName field (e.g., a DNS name).
Allows referencing services from another namespace or external systems.

Ingress Controllers for HTTP Routing:

Ingress Controllers provide HTTP and HTTPS routing to services based on the requested host, URI, or other information present in the request headers. They act as an API gateway, enabling more complex routing and allowing for features like SSL termination, load balancing, and path-based routing.

```
 apiVersion: Specifies the API version for the resource being created (v1 for Services).
 kind: Defines the type of resource (Service in this case).
 metadata: Contains metadata about the Service, including its name.
 spec: Specifies the desired state for the Service.
 selector: Labels used to select the pods to expose via the service (matching the labels of the Nginx Deployment pods).
 ports: Specifies the ports configuration.
 protocol: Specifies the protocol (TCP in this case).
 port: Specifies the port on the service.
 targetPort: Specifies the port to which the service will forward traffic within the selected pods.
 type: Specifies the type of (ClusterIP, NodePort, LoadBalancer, or ExternalName).
 ```

To apply any of these Service configuration, save the YAML content to a file and use the kubectl apply command:  

```
kubectl apply -f nginx-service.yaml

kubectl get service
kubectl get svc
kubectl describe svc kubernetes

```

Remember to save each configuration to separate files 
(e.g., nginx-clusterip-service.yaml, nginx-nodeport-service.yaml, nginx-loadbalancer-service.yaml, and external-service.yaml) 
and apply them using kubectl apply -f <filename> for each service type. 
Note that LoadBalancer services may require additional configuration based on your cloud provider. 

```
curl http://10.244.0.2

TargetPort: 80
Service Port: 80, ClusterIP Address
NodePort: 3008
```


## Scaling with Kubernetes Deploymnets

Managing Replicas: Horizontal and Vertical Scaling.

Horizontal Scaling: Increasing or decreasing the number of pod replicas based on demand.

Vertical Scaling: Adjusting the resources (CPU, memory) allocated to individual pods.

Hook

Imagine an online streaming platform gearing up for the premiere of a highly anticipated series. As the clock ticks down to the release time, viewers from around the world start logging in simultaneously, generating an unprecedented surge in traffic. Now, picture a scenario where this platform seamlessly scales its infrastructure to handle the skyrocketing demand without a glitch. This seamless orchestration of scaling and updates is not just a dream but a reality powered by Kubernetes. 

- What is Horizontal Pod Auto Scaling, When we need to use this kind of autoscaling.
- What is Vertical Pod Auto Scaling, When we need to use this kind of autoscaling.
- How we can use these through YAML files
- Cost optimization - Scale applications up or down based on demand
- What is Cluster Auto Scaling, how is it different from HPA / VPA?

```
kubectl scale deployment voting-app-deploy --replicaas=3
kubectl get deployments voting-app-deploy
kubectl get pods
```

Introduction for Container Orchestration

- Docker is by-and-far the leader. Defines a container format(Dockerfile, registry to host containers (public. and private)
- Auto-scaling, cloud-agnostic-yet-integratable technologies
- Evaluation/Training - minikube (local version of k8s)
- Development - mininkube, dev cluster on a cloud provider
- Deployment - cloud provider or bare metal
- k8s. on AWS can be set. up directly on EC2 instances by hand or using kops, which can produce grade k8s installation, upgrades, and management - maintained by the CNCF
- GCP has high-level support for Kubernetes through its GKE(Google Container Engine) offering, automates cluster setup, maitenance, monitoring, scaling, health checking

Understanding and Using Containers

- A container is a self-contained application. The kernal namespaces. provide stict isolation between system components at different levels
  
  - network, file, users, processes, IPCs
  
- The container runtime is running a host platform and establishes communication between the local host kernel and the container. The container runtime allows for starting and running the container on top of the host OS. The container runtime is responseible for all parts of running the container which are not already a part of the running container program itself.
  
  - docker, podman, lxc, runc, cri-o
  
- Docker is importatnt in the container landscape,
  - Dockerfile, which is a method for building container images.
  - A way to mangage container images, run containers, manage container instances, share container images
  
- Images are read-only enviornments that conaitn the runtime environment which includes the application and alll libraries it requires

- Registries are used to storage images. Docker Hub is a common registry, but provide registries can be created also

- Containers are the isolated runtime environments where the application is running. By using the namespaces the containers can be offered as a strictly isolated environment.

Kubernetes-As-A-Service
- Provide provisions VMs
- Provide installs Kubernetes
- Provide maintains VMs
- Google Container Engine (GKE)

```
gcloud container clusters get-credentials example-voting-app --zone us-central1-c --project example-voting-app-283506
kubectl get nodes
git clone https://.../example-voting-app.git
cd example-voting-app/
cd k8s-specifications/
ls

kubectl create -f voting-app-deploy.yaml
kubectl create -f voting-app-service.yaml
kubectl create -f redis-app-deployment.yaml
kubectl create -f redis-app-service.yaml
kubectl create -f postgres-deployment.yaml
kubectl create -f postgres-service.yaml
kubectl create -f worker-app-deployment.yaml
kubectl create -f worker-app-service.yaml

kubectl get deployments, svc

```

- AWS EKS
```
aws eks --region us-west-2 update-kubeconfig --name example-voting-app
kubectl get nodes

git clone https://.../example-voting-app.git
cd example-voting-app/
ls

kubectl create -f voting-app-deploy.yaml
kubectl create -f voting-app-service.yaml
kubectl create -f redis-app-deployment.yaml
kubectl create -f redis-app-service.yaml
kubectl create -f postgres-deployment.yaml
kubectl create -f postgres-service.yaml
kubectl create -f worker-app-deployment.yaml
kubectl create -f worker-app-service.yaml

kubectl get deployments, svc
```
