# Hands-on Open Liberty InstantOn Lab

In this lab, you will get to build a simple Open Liberty application and run it in a container, which you will then get to deploy in multiple ways.

Note that in many of the commands listed below, we have supplied a file to perform the command. You can either choose to type the commands yourself or simply run the script.

This lab requires you start at least one terminal session, and start the Chrome browser.

## Initial lab setup

### 1. Login as root

From the terminal, login as root:

```bash
$ su
```

Use password: `1l0veibmrh`

### 2. Clone the application from GitHub

```bash
$ cd Lab-InstantOn
$ git clone https://github.com/rhagarty/techxchange-instanton-lab.git
$ cd techxchange-instanton-lab/finish
```

### 3. Login to the OpenShift console, using the following URL:

```bash
https://console-openshift-console.apps.ocp.ibm.edu
```

Use username: `ocadmin` and password: `ibmrhocp`

### 4. Login to the OpenShift CLI

From the OpenShift console UI, click the username in the top right corner, and select `Copy login command`.

<TODO: add image>

Press `Display Token` and copy the top command and paste it into your terminal window. You should receive a confirmation message that your are logged in.

<TODO: add image>

## Build and run the application locally

### 1. Package the application

First ensure that you are in the right directory, then package the application.

```bash
$ cd Lab-InstantOn/techxchange-instanton-lab/finish
$ mvn package
```

### 2. Build the application image

```bash
$ ./build-local-without-instanton.sh
```

OR

```bash
$ sudo podman build -t dev.local/getting-started .
```

<TODO: Need sudo???>


> **NOTE**: The Dockerfile is using a slim version of the Java 17 Open Liberty UBI.
> 
> `FROM icr.io/appcafe/open-liberty:kernel-slim-java17-openj9-ubi`
> 

### 3. Run the application in a container

```bash
$ ./run-local-without-instanton.sh
```

OR 

```bash
$ sudo podman run --name getting-started --rm -p 9080:9080 dev.local/getting-started
```

Note the amount of time Open Liberty takes to report it has started (typically 3-5 seconds).

Check out the application by pointing your browser at http://localhost:9080/dev. 

To stop the running container, press `CTRL+C` in the command-line session where you ran the podman run command.

### 4. Update the Dockerfile to use InstantOn

In order to convert this image to use InstantOn, modify the Dockerfile by adding the following line to the bottom of the file. 

```bash
RUN checkpoint.sh afterAppStart
```

This command will perform the following actions:
1. Run the application
1. Take a checkpoint after the application code has loaded
1. Stop the application

Note that there are 2 checkpoint options:

`beforeAppStart`: Perform a checkpoint is after inspecting the application and parsing the application annotations, metadata, etc, but BEFORE any application code is run.  

`afterAppStart`: Perform a checkpoint after running any application code that has to run before the JVM can report that the app has started and is ready to receive requests. This checkpoint is inappropriate if your application start code does any of the following:
* Accessing a remote resource, such as a database
* Reading configuration that is expected to change when the application is deployed
* Starting a transaction

### 5. Build the application image with the InstantOn checkpoint

```bash
$ ./build-local-with-instanton.sh
```
OR 

```bash
$ sudo podman build \
   -t dev.local/getting-started-instanton \
   --cap-add=CHECKPOINT_RESTORE \
   --cap-add=SYS_PTRACE\
   --cap-add=SETPCAP \
   --security-opt seccomp=unconfined .
```

> **IMPORTANT**: We need to add several Docker capabilies to allow the image to be built.

You should see the following in the build output:

```bash
...
Performing checkpoint --at=afterAppStart
...
```

### 6. Run the InstantOn application in a container

```bash
$ ./run-local-with-instanton.sh
```

OR 

```bash
$ podman run \
  --rm \
  --cap-add=CHECKPOINT_RESTORE \
  --cap-add=SETPCAP \
  --security-opt seccomp=unconfined \
  -p 9080:9080 \
  dev.local/getting-started-instanton
```

> **IMPORTANT**: We need to add several Docker capabilies and security options so that the container has the correct privileges when running.

Note the startup time and compare to the version without InstantOn. You should see a startup time in the 300 millisecond range - a 10x improvement!

Check out the application by pointing your browser at http://localhost:9080/dev. 

To stop the running container, press `CTRL+C` in the command-line session where you ran the podman run command.

## Push the images to the OpenShift registry

### 1. Login to the OpenShift registry

```bash
$ oc registry login --insecure=true
```

### 2. Create the "dev" namespace and set it as the default

```bash
$ kubectl create ns dev
$ kubectl config set-context --current --namespace=dev
```

### 3. Enable the default registry route in OpenShift to push images to its internal repos

```bash
$ oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge
```

### 4. Login to the OpenShift registry

First we need to get the `TOKEN` that we can use to get the password for the registry.

```bash
$ oc get secrets -n openshift-image-registry | grep cluster-image-registry-operator-token
```

Take note of the `TOKEN` value, as you need to substitute it in the following command that sets the registry password.

```bash
$ export OCP_REGISTRY_PASSWORD=$(oc get secret -n openshift-image-registry cluster-image-registry-operator-token-<INPUT_TOKEN> -o=jsonpath='{.data.token}{"\n"}' | base64 -d)
```

Now set the OpenShift registry host value.

```bash
$ export OCP_REGISTRY_HOST=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}')
```

Finally, we have the values needed to login to the OpenShift registry.

```bash
$ podman login -p $OCP_REGISTRY_PASSWORD -u kubeadmin $OCP_REGISTRY_HOST --tls-verify=false
```

### 5. Tag and push our 2 application images to the OpenShift registry

Use `podman images` to verify our 2 local images:


Now tag and push them to the OpenShift registry:

```bash
$ // base application image
$ podman tag dev.local/getting-started:latest $(oc registry info)/$(oc project -q)/getting-started:1.0-SNAPSHOT
$ podman push $(oc registry info)/$(oc project -q)/getting-started:1.0-SNAPSHOT --tls-verify=false

$ // InstantOn application image
$ podman tag dev.local/getting-started-instanton:latest $(oc registry info)/$(oc project -q)/getting-started-instanton:1.0-SNAPSHOT
$ podman push $(oc registry info)/$(oc project -q)/getting-started-instanton:1.0-SNAPSHOT --tls-verify=false
```

### 6. Verify the images have been pushed to the OpenShift image repository

```bash
$ oc get imagestream
```

## Setup the OpenShift Cloud Platform (OCP) environment

### 1. Install the Liberty Operator

The Liberty Operator provides resources and configurations that make it easier to run Open Liberty applications in OCP services, such as Kubernetes and Knative.

```bash
$ kubectl apply --server-side -f https://raw.githubusercontent.com/OpenLiberty/open-liberty-operator/main/deploy/releases/1.2.1/kubectl/openliberty-app-crd.yaml
```

### 2. Apply the Liberty Operator to our namespace

```bash
$ OPERATOR_NAMESPACE=dev
$ WATCH_NAMESPACE=dev
curl -L https://raw.githubusercontent.com/OpenLiberty/open-liberty-operator/main/deploy/releases/1.2.0/kubectl/openliberty-app-operator.yaml \
      | sed -e "s/OPEN_LIBERTY_WATCH_NAMESPACE/${WATCH_NAMESPACE}/" \
      | kubectl apply -n ${OPERATOR_NAMESPACE} -f -
```

### 3. Install the Cert Manager 

```bash
$ kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.12.3/cert-manager.yaml
```

### 4. Apply the OpenShift serverless operator

This command requires the file `serverless-substriction.yaml`, which is provided in this repo.

```bash
$ oc apply -f serverless-subscription.yaml
```

Use the following command to determine when the service is successful.

```bash
$ oc get csv
```

### 5. Verify the Knative service is ready

```bash
$ oc get knativeserving.operator.knative.dev/knative-serving -n knative-serving --template='{{range .status.conditions}}{{printf "%s=%s\n" .type .status}}{{end}}'
```

### 6. Edit the Knative permissions to allow to add Capabilities

```bash
$ kubectl -n knative-serving edit cm config-features -oyaml
```

Add in the following line just bellow the “data” tag at the top:
```bash
kubernetes.containerspec-addcapabilities: enabled
```

> **IMPORTANT**: to save your change and exit the file, hit the escape key, then type `:x`. 

### 7. Run the following commands to give our application the correct Service Account and Security Context Contraint to run instantOn

```bash
$ oc create serviceaccount instanton-sa
$ oc apply -f scc-cap-cr.yaml
$ oc adm policy add-scc-to-user cap-cr-scc -z instanton-sa
```

## Deploy the applications to OCP

### 1. Deploy the base application

```bash
$ kubectl apply -f deploy-without-instanton.yaml
```

### 2. Monitor the base application

```bash
$ kubectl get pods
```

Once the pod is running and displays a `POD NAME`, quickly take a look at the pod log to see how long the application took to start up.

```bash
$ kubectl logs <POD NAME>
```

> **NOTE**: Knative will stop the pod does not receive a request in specified time frame, which is set in a configuration yaml file. For our lab, the settings are in <FILE NAME>, and set to 20 seconds.

<TODO: SHOW FILE>

### 3. Deploy the application with InstantOn

```bash
$ kubectl apply -f deploy-with-instanton.yaml
```

Use the same commands as above to monitor the application.

Compare the start times of both applications and note how the InstantOn version again starts around 10x faster.

### 4. Verify the applications are running

To get the URL for the deployed applications, use the following command:

```bash
$ kubectl get ksvc
```

Check out each of the applications by pointing your browser at the listed URL.

### 5. Visually test how long an idle application takes to re-start

As a visual test, do not click or refresh either application running in the browser for over 20 seconds. This will cause the knative service to stop the associated pod.

Now, one application at a time, click the refresh button on the application page to see how long it takes to refresh the content.

### 6. (OPTIONAL) Stop and delete the deployed applications

```bash
$ kubectl delete -f deploy-without-instanton.yaml
$ kubectl delete -f deploy-with-instanton.yaml
```

## Troubleshooting

If you run into the following error when building the InstantOn application image:

```bash
CWWKE0963E: The server checkpoint request failed because netlink system calls were unsuccessful. If SELinux is enabled in enforcing mode, netlink system calls might be blocked by the SELinux "virt_sandbox_use_netlink" policy setting. Either disable SELinux or enable the netlink system calls with the "setsebool virt_sandbox_use_netlink 1" command.
Error: building at STEP "RUN checkpoint.sh afterAppStart": while running runtime: exit status 74
```

Run the following command from your terminal window:

```bash
setsebool virt_sandbox_use_netlink 1
```