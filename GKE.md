# Deploying a .NET Framework web application to a GKE Cluster with a Windows Server Node Pool 

## Enabling Google APIs

In [Cloud Shell](https://shell.cloud.google.com), run the following command to enable the Cloud Build, GKE, Container Registry, Compute Engine, and Cloud Build APIs in your project:

```bash
gcloud services enable container.googleapis.com containerregistry.googleapis.com run.googleapis.com compute.googleapis.com cloudbuild.googleapis.com
```

## Setup Cloud SQL for SQL Server

If you haven't done so already, [create](./README.md#Setup-Cloud-SQL-for-SQL-Server) a Cloud SQL for SQL Server instance to host the Contoso University database.

### Configuring private IP for Cloud SQL for SQL Server

GKE uses cluster auto-scaling, meaning that under load your cluster may add new nodes to the cluster. New nodes are added with new external IPs, which makes it hard to keep your authorized networks in Cloud SQL up-to-date. To  allow traffic from GKE nodes to your Cloud SQL instance, we recommended that you enable private IP for your Cloud SQL instance.

If you haven't done so already, follow the [instructions](https://cloud.google.com/sql/docs/sqlserver/configure-private-ip) to configure a private IP for your Cloud SQL instance. Note the instance's private IP, as you use it later in this tutorial. 

## Creating the GKE cluster

Still in Cloud Shell, create a GKE cluster with a Windows Server node pool:

```bash
export CLUSTER_NAME=cluster1

gcloud container clusters create $CLUSTER_NAME \
    --enable-ip-alias \
    --num-nodes=1 \
    --zone=us-central1-a \
    --release-channel regular

gcloud container node-pools create windows-ltsc-pool \
    --cluster=$CLUSTER_NAME \
    --image-type=WINDOWS_LTSC \
    --no-enable-autoupgrade \
    --zone=us-central1-a \
    --machine-type=n1-standard-2 \
    --num-nodes=1
```

Refer to [creating a cluster using Windows Server node pools](https://cloud.google.com/kubernetes-engine/docs/how-to/creating-a-cluster-windows) for more information about Windows Server node pools in GKE.

## Getting the code

If you plan on building and running the container locally, execute the following commands in a Windows Server 2019 machine that has [Docker](https://cloud.google.com/compute/docs/containers#install_docker) and [git](https://git-scm.com/download/win) installed. Alternatively, if you wish to build the container image with Cloud Build, remain in Cloud shell.

Run the following command to download the code you use in this tutorial:

```bash
git clone https://github.com/GoogleCloudPlatform/dotnet-migration-sample

cd dotnet-migration-sample 
```

NOTE: In this tutorial you create several files, such as a Docker file and a build instruction file for Cloud Build. If you want to skip the steps for creating the required files, checkout the `gke_windows` branch:
```bash
git checkout gke_windows 
```

## Treating the connection string as a secret
The database connection string contains sensitive information - the user's credentials. It is a security best practice to separate the sensitive information, also known as secrets, from the application. In GKE, application's secrets are stored in the cluster as a kubernetes secret and are deployed to the container as either files or environment variables, together with the application. 

1. To reference this secret with no code changes, replace the `connectionStrings` section in the `ContosoUniversity\Web.config` file with the following configuration (copy only the `connectionStrings` line from the below snippet): 

   ```xml
   <configuration>
     ...
     <connectionStrings configSource="secret\connectionStrings.config"/>
     ...
   </configuration>
   ```

1. Create a file named `connectionStrings.config` in the same folder as the `ContosoUniversity.sln` file and add the `connectionStrings` section to the file:

   ```xml
   <connectionStrings>
       <add name="SchoolContext"
          connectionString="Data Source=[INSTANCE_IP];Initial Catalog=ContosoUniversity;User ID=[USER];Password=[PASSWORD];"
          providerName="System.Data.SqlClient" />
   </connectionStrings>
   ```

   Replace `[INSTANCE_IP]`, `[USER]`, and `[PASSWORD]` with the **private** IP of your SQL Server instance that you created before, the user you created, and the password you have set for the user.

1. Run the following command to create the kubernetes secret from the `connectionStrings.config` file:

   ```bash
   kubectl create secret generic connection-strings --from-file=connectionStrings.config
   ```

When deploying the application to GKE, kubernetes mounts the secret as a file, to a subdirectory of the application. The application in this tutorial is deployed to `C:\inetpub\wwwroot`, and the newly created secret is deployed to the `secret` directory under the application's path. The following snippet from the `deploy.yaml` deployment file, which you create later in this tutorial, shows how to mount the secret to the container:

```yaml
        volumeMounts: 
        - name: connection-strings
          mountPath: "/inetpub/wwwroot/secret"
          readOnly: true        
...
      volumes:
      - name: connection-strings
        secret:
          secretName: connection-strings
```

NOTE: Specifying a mount directory outside the path of the application is a risk, as IIS might not have permissions to read the file, which will result in an HTTP 500 error.  

## Creating the Windows Container image

To deploy the web application to GKE, you need to create a [Dockerfile](https://docs.docker.com/engine/reference/builder/) that describes how to build the application with MSBuild and how to create the container image, and then build the container image and push it to a container repository. Next, you create the Dockerfile, then build the container image using Cloud Build, and push it to your private Container Registry.

### Creating the Dockerfile
Create a file named `Dockerfile` in the same folder as the `ContosoUniversity.sln` file and set its content:

```dockerfile
# escape=`

FROM mcr.microsoft.com/dotnet/framework/sdk:4.8-windowsservercore-ltsc2019 AS build
WORKDIR /source
COPY . /source

RUN msbuild ContosoUniversity.sln /t:restore /p:RestorePackagesConfig=true
RUN msbuild /p:Configuration=Release `
	/t:WebPublish `
	/p:WebPublishMethod=FileSystem `
	/p:publishUrl=C:\deploy

FROM mcr.microsoft.com/dotnet/framework/aspnet:4.8-windowsservercore-ltsc2019 AS runtime
COPY --from=build /deploy /inetpub/wwwroot

EXPOSE 80
```

The container image runs .NET Framework 4.8. The application was written for .NET Framework 4.5, but because of .NET Framework's backward compatibility, the container will be able to run the application even though it targets .NET 4.5.

### Optional - Building and testing the container locally

If you have Docker installed locally on your Windows Server 2019 machine, and you want to test the container locally, follow the step below. If you do not want to test the container locally, skip this section and use [Cloud Build](#Using-Cloud-Build-to-build-Windows-container-images).  

1. In Cloud Shell, build the container by running the following commands:

   ```cmd
   # GKE is not used - Copy the connectionStrings.config file to the secret folder
   md secret
   copy connectionStrings.config secret

   # Store the Project env variable
   gcloud info --format=value(config.project) > __project && set /p PROJECT= < __project && del __project

   # Build the container
   docker build -t gcr.io/%PROJECT%/contosouniversity-windows:v1 -f Dockerfile .

   # Run the container
   docker run -it --rm -p 8080:80 -v "%cd%\secret:c:\inetpub\wwwroot\secret" --name contoso-university gcr.io/%PROJECT%/contosouniversity-windows:v1
   ```

   You should now be able to launch a browser with [http://localhost:8080](http://localhost:8080) to see the application.

1. Run the following command to register gcloud as a Docker credential helper:
   ```cmd
   gcloud auth configure-docker
   ```
1. Push the container to your private container registry:
   ```cmd
   docker push gcr.io/%PROJECT%/contosouniversity-windows:v1
   ```

## Using Cloud Build to build Windows container images

Cloud Build workers are linux-based and therefore do not support building .NET Framework applications. However, you can use Cloud Build workers to run a script that creates a Windows Server VM with the .NET Framework SDK, copy the code to the VM, and run MSBuild to build your application. These build steps are available by using the [gke-windows-builder](https://cloud.google.com/kubernetes-engine/docs/tutorials/building-windows-multi-arch-images) builder for Cloud Build. 
Next, you use the `gke-windows-builder` with Cloud Build to build the Windows Server container image.

NOTE: The `gke-windows-builder` is not specific to GKE. Although built by the GKE Windows engineering team, it doesn't use or depends on GKE.  

1. In Cloud Shell, run the following commands to allow the Cloud Build service account access to your project:

   ```bash
   export PROJECT=[PROJECT]
   gcloud config set project $PROJECT

   export CLOUD_BUILD_SA=$(gcloud projects describe $PROJECT --format 'value(projectNumber)')@cloudbuild.gserviceaccount.com

   gcloud projects add-iam-policy-binding $PROJECT \
      --member=serviceAccount:$CLOUD_BUILD_SA \
      --role='roles/compute.instanceAdmin'

   gcloud projects add-iam-policy-binding $PROJECT \
      --member=serviceAccount:$CLOUD_BUILD_SA \
      --role='roles/iam.serviceAccountUser'

   gcloud projects add-iam-policy-binding $PROJECT \
      --member=serviceAccount:$CLOUD_BUILD_SA \
      --role='roles/compute.networkViewer'

   gcloud projects add-iam-policy-binding $PROJECT \
      --member=serviceAccount:$CLOUD_BUILD_SA \
      --role='roles/storage.admin'

   gcloud compute firewall-rules create allow-winrm-ingress \
      --allow=tcp:5986 \
      --direction=INGRESS
    ```

   Replace `[PROJECT]` with your project ID.

1. Create a file named `cloudbuild.yaml` in the same folder as the `ContosoUniversity.sln` file and set its content:

   ```yaml
   timeout: 3600s
   steps:
   - name: 'gcr.io/gke-release/gke-windows-builder:release-2.6.1-gke.0'
     args:
     - --versions
     - 'ltsc2019'
     - --container-image-name
     - 'gcr.io/$PROJECT_ID/contosouniversity-windows:v1'
   ```  

1. Use Cloud Build to build the Windows Server container image and push the image to Container Registry:

   ```bash
   gcloud builds submit
   ```
   
## Deploy to GKE
Now that the container image is ready, you can create the deployment in GKE and test the web application to verify it is working and able to query the SQL Server database.

1. Create a file named `deploy.yaml` in the same folder as the `ContosoUniversity.sln` file and set its content:

   ```yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     labels:
       app: contosouniversity
     name: contosouniversity
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: contosouniversity
     template:
       metadata:
         labels:
           app: contosouniversity
       spec:
         containers:
         - image: gcr.io/${PROJECT}/contosouniversity-windows:v1
           imagePullPolicy: IfNotPresent
           name: contosouniversity-container
           volumeMounts: 
           - name: connection-strings
             mountPath: "/inetpub/wwwroot/secret"
             readOnly: true        
           ports:
           - containerPort: 80
             protocol: TCP
         nodeSelector:
           kubernetes.io/os: windows
         volumes:
         - name: connection-strings
           secret:
             secretName: connection-strings
         restartPolicy: Always
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: contosouniversity-service
   spec:
     selector:
       app: contosouniversity
     ports:
       - protocol: TCP
         port: 80
         targetPort: 80
     type: LoadBalancer
   ```

1. Run the following command to deploy the Contoso University web application to GKE:
   ```bash
   envsubst < deploy.yaml | kubectl apply -f -
   ```

   The script uses the `envsubst` tool to substitute `${PROJECT}` in the `deploy.yaml` file with your project ID. The output of that script is applied to your GKE cluster. You can see the relevant placeholder in the `deploy.yaml` file below:

   ```yaml
         containers:
         - image: gcr.io/${PROJECT}/contosouniversity-windows:v1
   ```
