
#### What is Docker

- Docker is a platform that allows you to "build, shipa nd run any app, anywhere".Docker enables you to seperate your applications from your infrastructre so you can deliver software quickly.

- Docker daemon. Docker_Hosts. Docker Engine, Docker Server. Docker daemon listened for Docker API requests and manages Docker objects ushc as images, containers, networks, and volumes. A daemon can also communicate with other daemons to mange Docker servies.

- Docker client is the primary way that many Docker users interact with Docker. When you use commands such as "docker run", the client sends these commands to docker daemon.

- Docker registry stores docker images. Docker Hub is a public registry that anyone can use, and Docker is configured to look for images on Docker Hub by default. A registry is where we store our images. You can host your own registry, or you can use Docker's public registry which is called DockerHub. Inside a registry, images are stored in repositories.

- Docker repository is a collection of different docker images with the same name, that have different tags, each tag usually represents a different version of the image. 
  - Docker will use latest as a default tag when no tag is provided. 
  - A lot of repositories use it to tag the most up-to-date table image.  However, this is still only. a convention and is entirely not being enforced.
  - Images which are tagged latest will not be updated automatically when a newer version of the image is pushed to the repository.

- Docker image is a read-only template with instructions for creating a Docker container. Often, an image is based on another image, with some additional customization. Images is read-only templates used to create containers. Docker Image Layers - All changes made into the running containers will be written into the writable layer. When the container is deleted, the wirtable layer is also deleted, but the underlying image remains unchanged. Multiple containers can share access to the same underlying image.

- Docker container is a runnable instance of an image. By default, a conatiner is relatively well isolated from other containers and its host machine. When a container is removed, any changes to its state that are not stored in persistent storage disappear. Containers is lightweight and portable encapsulations of an environment in which to. run applications. If an image is a class, then a container is an instance of a class - a runtime object.  Container are created from images. Inside a container, if has all teh ibnaries and dependencies to run the application.
Docker

```
# List running containers
docker ps

# List all images and their sizes
docker images

# Remove unused images (reclaim disk space)
docker system prune -a

# Check GPU usage inside a running container
docker exec -it <container_id> nvidia-smi

# Copy a file from container to host
docker cp <container_id>:/workspace/results.csv ./results.csv

# View container logs
docker logs -f <container_id>
```

https://docs.docker.com/engine/reference/commandline/build/

https://docs.docker.com/engine/reference/builder/

#### Layers

A *layer* is a modification applied to a Docker image as represented by an instruction in a Dockerfile. Typically, a layer is created when a base image is changed—for example, consider a Dockerfile that looks like this:

```
FROM ubuntu

Run mkdir /tmp/logs

RUN apt-get install vim

RUN apt-get install htop
```

Now in this case, Docker will consider Ubuntu image as the base image and add three layers:

- One layer for creating /tmp/logs
- One other layer that installs vim
- A third layer that installs htop

When Docker builds the image, each layer is stacked on the next and merged into a single layer using the union filesystem. Layers are uniquely identified using sha256 hashes. This makes it easy to reuse and cache them. When Docker scans a base image, it scans for the IDs of all the layers that constitute the image and begins to download the layers. If a layer exists in the local cache, it skips downloading the cached image.

#### Docker Image

Docker image is a read-only template that forms the foundation of your application. It is very much similar to, say, a shell script that prepares a system with the desired state. In simpler terms, it’s the equivalent of a cooking recipe that has step-by-step instructions for making the final dish.

A Docker image starts with a base image—typically the one selected is that of an operating system are most familiar with, such as Ubuntu. On top of this image, we can add build our application stack adding the packages as and when required.

There are many pre-built images for some of the most common application stacks, such as Ruby on Rails, Django, PHP-FPM with nginx, and so on. On the advanced scale, to keep the image size as low as possible, we can also start with slim packages, such as Alpine or even Scratch, which is Docker’s reserved, minimal starting image for building other images.

Docker images are created using a series of commands, known as instructions, in the Dockerfile. The presence of a Dockerfile in the root of a project repository is a good indicator that the program is container-friendly. We can build our own images from the associated Dockerfile and the built image is then published to a registry. We will take a deeper look at Dockerfile in later chapters. For now, consider the Docker image as the final executable package that contains everything to run an application. This includes the source code, the required libraries, and any dependencies.

#### Docker Container

A Docker image, when it’s run in a host computer, spawns a process with its own namespace, known as a *Docker container*. The main difference between a Docker image and a container is the presence of a thin read/write layer known as the container layer. Any changes to the filesystem of a container, such as writing new files or modifying existing files, are done to this writable container layer than the lower layers.

An important aspect to grasp is that when a container is running, the changes are applied to the container layer and when the container is stopped/killed, the container layer is not saved. Hence, all changes are lost. This aspect of containers is not understood very well and for this reason, stateful applications and those requiring persistent data were initially not recommended as containerized applications. However, with Docker Volumes, there are ways to get around this limitation. We discuss Docker Volumes more in Chapter [5](https://learning.oreilly.com/library/view/practical-docker-with/9781484237847/html/463857_1_En_5_Chapter.xhtml), “Understanding Docker Volumes”.

#### Bind Mounts and Volumes

We mentioned previously that when a container is running, any changes to the container are present in the container layer of the filesystem. When a container is killed, the changes are lost and the data is no longer accessible. Even when a container is running, getting data out of it is not very straightforward. In addition, writing into the container’s writable layer requires a storage driver to manage the filesystem. The storage driver provides an abstraction on the filesystem available to persist the changes and this abstraction often reduces performance.

For these reasons, Docker provides different ways to mount data into a container from the Docker host: volumes, bind mounts, and tmpfs volumes. While tmpfs volumes are stored in the host system’s memory only, bind mounts and volumes are stored in the host filesystem.

We explore Docker Volumes in detail in Chapter [5](https://learning.oreilly.com/library/view/practical-docker-with/9781484237847/html/463857_1_En_5_Chapter.xhtml), “Understanding Docker Volumes”.

#### Docker Registry

We mentioned earlier that you can leverage existing images of common application stacks—have you ever wondered where these are and how you can use them in building your application? A Docker Registry is a place where you can store Docker images so that they can be used as the basis for an application stack. Some common examples of Docker registries include the following:

- Docker Hub
- Google Container Registry
- Amazon Elastic Container Registry
- JFrog Artifactory

Most of these registries also allow for the visibility level of the images that you have pushed to be set as public/private. Private registries will prevent your Docker images from being accessible to the public, allowing you to set up access control so that only authorized users can use your Docker image.

#### Dockerfile

A *Dockerfile* is a set of instructions that tells Docker how to build an image. A typical Dockerfile is made up of the following:

- A FROM instruction that tells Docker what the base image is
- An ENV instruction to pass an environment variable
- A RUN instruction to run some shell commands (for example, install-dependent programs not available in the base image)
- A CMD or an ENTRYPOINT instruction that tells Docker which executable to run when a container is started

As you can see, the Dockerfile instruction set has clear and simple syntax, which makes it easy to understand. We take a deeper look at Dockerfiles later in the book.

#### Docker Engine

Docker Engine is the core part of Docker. Docker Engine is a client-server application that provides the platform, the runtime, and the tooling for building and managing Docker images, Docker containers, and more. Docker Engine provides the following:

- Docker daemon
- Docker CLI
- Docker API

##### Docker Daemon

- The Docker daemon is a service that runs in the background of the host computer and handles the heavy lifting of most of the Docker commands. The daemon listens for API requests for creating and managing Docker objects, such as containers, networks, and volumes. Docker daemon can also talk to other daemons for managing and monitoring Docker containers. Some examples of inter-daemon communication include communication Datadog for container metrics monitoring and Aqua for container security monitoring.

##### Docker CLI

Docker CLI is the primary way that you will interact with Docker. Docker CLI exposes a set of commands that you can provide. The Docker CLI forwards the request to Docker daemon, which then performs the necessary work.

While the Docker CLI includes a huge variety of commands and sub-commands, the most common commands that we will work with in this book are as mentioned:

docker build

docker pull

docker run

docker exec

```
docker run ubuntu echo hello world
```

##### Docker API

Docker also provides an API for interacting with the Docker Engine. This is particularly useful if there’s a need to create or manage containers from within applications. Almost every operation supported by the Docker CLI can be done via the API.

The simplest way to get started by Docker API is to use curl to send an API request. For Windows Docker hosts, we can reach the TCP endpoint:
```
curl http://localhost:2375/images/json

[{"Containers":-1,"Created":1511223798,"Id":"sha256:f2a91732366c0332ccd7afd2a5c4ff2b9af81f549370f7a19acd460f87686bc7","Labels":null,"ParentId":"","RepoDigests":["hello-world@sha256:66ef312bbac49c39a89aa9bcc3cb4f3c9e7de3788c944158df3ee0176d32b751"],"RepoTags":["hello-world:latest"],"SharedSize":-1,"Size":1848,"VirtualSize":1848}]
```

On Linux and Mac, the same effect can be achieved by using curl to send requests to the UNIX socket:

```
curl --unix-socket /var/run/docker.sock -X POST http://images/json

[{"Containers":-1,"Created":1511223798,"Id":"sha256:f2a91732366c0332ccd7afd2a5c4ff2b9af81f549370f7a19acd460f87686bc7","Labels":null,"ParentId":"","RepoDigests":["hello-world@sha256:66ef312bbac49c39a89aa9bcc3cb4f3c9e7de3788c944158df3ee0176d32b751"],"RepoTags":["hello-world:latest"],"SharedSize":-1,"Size":1848,"VirtualSize":1848}]
```

#### Docker Compose

Docker Compose is a tool for defining and running multi-container applications. Much like how Docker allows you to build an image for your application and run it in your container, Compose use the same images in combination with a definition file (known as the *compose file*) to build, launch, and run multi-container applications, including dependent and linked containers.

The most common use case for Docker Compose is to run applications and their dependent services (such as databases and caching providers) in the same simple, streamlined manner as running a single container application. 

#### HANDS-ON DOCKER

Open a terminal window and type the following command:

```
docker info
```

#### Working with Docker Images

Let’s look at the available Docker images. To do this, type the following command:

**docker image ls** able to look at the available Docker images

The **docker inspect** command provides a lot of information about the image. Of importance are the image properties **Env**, **Cmd**, and **Layers**, which tell us about these environment variables. They tell us which executable runs when the container is started and the layers associated with these environment variables.

```
docker image inspect hello-world | jq .[].Config.Env

[

 "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

]
```

Here’s the startup command on the container:

```
docker image inspect hello-world | jq .[].Config.Cmd

[

 "/hello"

]
```

Here are the layers associated with the image:

```
docker image inspect hello-world | jq .[].RootFS.Layers

[

 "sha256:f999ae22f308fea973e5a25b57699b5daf6b0f1150ac2a5c2ea9d7fecee50fdf"

]
```

Every Docker image has an associated tag. Tags typically include names and version labels. While it is not mandatory to associate a version tag with a Docker image name, these tags make it easier to roll back to previous versions. Without a tag name, Docker must fetch the image with the latest tag. You can also provide a tag name to force-fetch a tagged image.

Docker Store lists the different tags associated with the image. If you’re looking for a specific tag/version, it’s best to check Docker Store. Figure [2-3](https://learning.oreilly.com/library/view/practical-docker-with/9781484237847/html/463857_1_En_2_Chapter.xhtml#Fig3) shows a typical tag listing of an image.

```
docker pull nginx:1.12-alpine-perl

docker pull docker-private.registry:1337/nginx

docker login docker-private.registry:1337 - If the registry needs authentication, you can log in to the registry by typing docker login:

docker run -p 80:80 nginx
```

To list all the running containers, you can type docker ps - docker ps

```
docker stop <container-id>

docker ps shows the active, running containers

docker ps -a list all the containers

docker rm <container-id>  remove the containers 
```
