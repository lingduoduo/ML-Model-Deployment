# Docker for ML

A small, reproducible Docker setup for ML development, plus reference notes on
how Docker works. The goal: one container image that gives you (and your
teammates) the exact same Python + PyTorch environment, with models and data
mounted from the host so nothing is lost between rebuilds.

## What's in this directory

| File | What it is |
|------|-----------|
| [`Dockerfile`](Dockerfile) | **CPU** image — `python:3.12-slim` + PyTorch (CPU build) and the usual ML stack. ~Small, runs anywhere. |
| [`Dockerfile.nvidia-container-toolkit`](Dockerfile.nvidia-container-toolkit) | **GPU** image — `nvidia/cuda:12.4.1-devel` + CUDA-enabled PyTorch (`cu124`). Also bundles the NVIDIA Container Toolkit so `nvidia-ctk` is available inside the image. |
| [`docker-compose.yml`](docker-compose.yml) | Two-service dev stack: the `ai-dev` image above + a Qdrant vector database, for RAG-style work. |
| `Docker_for_ML.md`, `docker.md`, `docker-notes.md`, `Intro-Docker.md`, `Jenkins.md` | Longer-form reference notes. |

The two Dockerfiles are the same image recipe with one decision swapped: **what
to run on**.

| | CPU — [`Dockerfile`](Dockerfile) | GPU — [`Dockerfile.nvidia-container-toolkit`](Dockerfile.nvidia-container-toolkit) |
|---|---|---|
| Base image | `python:3.12-slim-bookworm` | `nvidia/cuda:12.4.1-devel-ubuntu22.04` |
| PyTorch | `torch==2.3.1` (default CPU wheels) | `torch==2.3.1 --index-url .../whl/cu124` |
| Needs a GPU? | No — runs on any machine | Yes — host needs an NVIDIA GPU + the Container Toolkit |
| Approx. size | ~hundreds of MB | several GB (CUDA toolchain) |
| Use for | inference on CPU, lightweight tools, CI | training/inference that needs CUDA |

Both images install the same ML libraries (`numpy`, `pandas`, `scikit-learn`,
`matplotlib`, `jupyter`, `transformers`, `datasets`, `accelerate`,
`safetensors`), expose port `8888` for Jupyter, set `WORKDIR /workspace`, and
declare `/workspace` and `/models` as volumes.

---

## Quick start

### 1. Install Docker

**macOS**

```bash
brew install --cask docker
open /Applications/Docker.app
```

**Ubuntu**

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# Log out and back in for the group change to take effect.
```

Verify:

```bash
docker --version
docker run hello-world
```

### 2. (GPU only) Install the NVIDIA Container Toolkit on the host

This step lets containers see your GPU. **macOS and Windows (WSL2) users can
skip it** — Docker Desktop handles GPU passthrough differently. It must run on
the Linux host that owns the Docker daemon (installing the toolkit *inside* an
image, as `Dockerfile.nvidia-container-toolkit` does, gives you the `nvidia-ctk`
binary but does **not** expose host GPUs — the host install below is what does).

```bash
sudo apt-get update
sudo apt-get install -y --no-install-recommends ca-certificates curl gnupg2
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

Test that containers can reach the GPU:

```bash
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
```

If you see your GPU listed, the toolkit is working.

### 3. Build the image

```bash
# CPU
docker build -t ai-dev -f Docker/Dockerfile .

# GPU
docker build -t ai-dev-gpu -f Docker/Dockerfile.nvidia-container-toolkit .
```

The first build takes a while (downloading the base image + PyTorch).
Subsequent builds reuse cached layers, so only changed steps rebuild.

### 4. Run it

Check the install:

```bash
# CPU
docker run --rm -it \
  -v $(pwd):/workspace \
  -v ~/models:/models \
  ai-dev python -c "import torch; print(f'PyTorch {torch.__version__}, CUDA: {torch.cuda.is_available()}')"

# GPU (note --gpus all)
docker run --rm -it --gpus all \
  -v $(pwd):/workspace \
  -v ~/models:/models \
  ai-dev-gpu python -c "import torch; print(f'PyTorch {torch.__version__}, CUDA: {torch.cuda.is_available()}')"
```

On the CPU image `CUDA: False` is expected; on the GPU image (with a GPU and
`--gpus all`) you should see `CUDA: True`.

Run Jupyter inside the container:

```bash
docker run --rm -it \
  -v $(pwd):/workspace \
  -v ~/models:/models \
  -p 8888:8888 \
  ai-dev jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser --allow-root
```

### 5. Mount data and models as volumes

Volume mounts are critical for ML work — without them, multi-GB model
downloads vanish when the container stops.

```bash
-v $(pwd):/workspace   # your code
-v ~/models:/models    # a shared models directory
-v ~/datasets:/data    # datasets
```

Load from the mounted path inside your script:

```python
from transformers import AutoModel

model = AutoModel.from_pretrained("/models/llama-7b")
```

The model lives on your host filesystem, so you can rebuild the container as
often as you like without re-downloading it.

### 6. Multi-service apps with Docker Compose

A RAG application typically needs an inference container **and** a vector
database. [`docker-compose.yml`](docker-compose.yml) runs both with one command.
It builds the CPU `Dockerfile` by default and starts Qdrant alongside it.

```bash
cd Docker
docker compose up -d
```

The `ai-dev` container can now reach Qdrant at `http://qdrant:6333` by service
name — Compose creates a shared network automatically:

```python
from qdrant_client import QdrantClient

client = QdrantClient(host="qdrant", port=6333)
print(client.get_collections())
```

Stop everything (add `-v` to also delete the Qdrant volume):

```bash
docker compose down
docker compose down -v
```

**To run the GPU image under Compose**, use
[`docker-compose.gpu.yml`](docker-compose.gpu.yml) — same stack, but it builds
the GPU Dockerfile and reserves an NVIDIA device (requires the host NVIDIA
Container Toolkit from step 2):

```bash
cd Docker
docker compose -f docker-compose.gpu.yml up -d
```

The device reservation it adds:

```yaml
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
```

### 7. Useful commands

```bash
docker ps                                   # running containers
docker images                               # all images and their sizes
docker system prune -a                      # remove unused images (reclaim disk)
docker exec -it <container_id> nvidia-smi   # GPU usage inside a running container
docker cp <container_id>:/workspace/results.csv ./results.csv
docker logs -f <container_id>               # follow container logs
```

---

## Concepts reference

A condensed tour of the pieces these files rely on. The longer notes
(`docker.md`, `docker-notes.md`) go deeper.

### Image

A Docker **image** is a read-only template with the instructions for creating a
container — think of it as a recipe that produces a known system state. An image
starts from a **base image** (often an OS such as Ubuntu, or a slim base like
Alpine or `scratch`) and layers your application stack on top: source code,
libraries, and dependencies. Images are built from a `Dockerfile` and published
to a registry. Many pre-built images exist for common stacks (PyTorch, Django,
nginx, …) so you rarely start from nothing.

### Container

A **container** is a running instance of an image — a process with its own
namespace, relatively isolated from other containers and the host. If an image
is a class, a container is an instance of it. The key difference is a thin
read/write **container layer** on top of the image's read-only layers: all
changes a running container makes go there. When the container is removed, that
layer is discarded and any state not written to a volume is lost. Multiple
containers can share the same underlying image.

### Layers

A **layer** is the change produced by one instruction in a `Dockerfile`. For:

```dockerfile
FROM ubuntu
RUN mkdir /tmp/logs
RUN apt-get install vim
RUN apt-get install htop
```

Docker takes `ubuntu` as the base and adds three layers (one per `RUN`). At
build time the layers are stacked and merged via a union filesystem. Each layer
is identified by a `sha256` hash, which makes layers easy to **cache and
reuse**: if a layer already exists locally, Docker skips rebuilding or
re-downloading it. This is why ordering Dockerfile steps from least- to
most-frequently-changed speeds up rebuilds.

### Bind mounts and volumes

Because a container's writable layer is discarded on removal — and writing to it
goes through a storage driver that adds overhead — Docker offers three ways to
persist or share data with the host:

- **Volumes** — managed by Docker, stored in the host filesystem.
- **Bind mounts** — map a specific host path into the container (what the `-v $(pwd):/workspace` flags above use).
- **tmpfs mounts** — stored only in the host's memory.

For ML work, mounting models and datasets as volumes is what keeps large
downloads alive across rebuilds.

### Registry and repository

A **registry** stores images. Docker Hub is the public default; others include
Google Container Registry, Amazon ECR, and JFrog Artifactory. Most support
public and private visibility with access control. Within a registry, images
live in **repositories** — a collection of images sharing a name, distinguished
by **tags** (usually versions). Docker uses `latest` when no tag is given; by
convention that points at the most recent image, but it is **not enforced** and
`latest` is **not** auto-updated when a newer image is pushed. Always pin a
version tag for reproducible builds.

### Dockerfile

A `Dockerfile` is the set of instructions Docker follows to build an image.
A typical one uses:

- `FROM` — the base image
- `ENV` — environment variables
- `RUN` — shell commands (e.g. installing dependencies)
- `CMD` / `ENTRYPOINT` — the executable to run when a container starts

The presence of a `Dockerfile` at a project's root is a good sign it's
container-friendly.

### Docker Engine

Docker Engine is the client-server core. It provides:

- **Docker daemon** — a background service that does the heavy lifting: it
  listens for API requests and manages images, containers, networks, and
  volumes. It can also talk to other daemons (e.g. Datadog for metrics, Aqua
  for security monitoring).
- **Docker CLI** — the primary way you interact with Docker. Commands like
  `docker build`, `docker pull`, `docker run`, and `docker exec` are forwarded
  to the daemon, which does the work.
- **Docker API** — the same operations exposed programmatically, for managing
  containers from inside applications. For example:

  ```bash
  # Windows host (TCP endpoint)
  curl http://localhost:2375/images/json

  # Linux / macOS (UNIX socket)
  curl --unix-socket /var/run/docker.sock http://localhost/images/json
  ```

### Docker Compose

Docker Compose defines and runs multi-container applications from a single
`compose` file. It uses the same images as plain Docker but coordinates them —
building, launching, and networking dependent and linked services (databases,
caches, …) together. The common case is running an app alongside its dependent
services with the same one-command simplicity as a single container, which is
exactly what [`docker-compose.yml`](docker-compose.yml) does for `ai-dev` +
Qdrant.

---

## Inspecting images

`docker image ls` lists local images; `docker image inspect` dumps detailed
metadata. Useful fields are `Config.Env`, `Config.Cmd`, and `RootFS.Layers`:

```bash
docker image inspect hello-world | jq '.[].Config.Env'
# [ "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" ]

docker image inspect hello-world | jq '.[].Config.Cmd'
# [ "/hello" ]

docker image inspect hello-world | jq '.[].RootFS.Layers'
# [ "sha256:f999ae22f308fea973e5a25b57699b5daf6b0f1150ac2a5c2ea9d7fecee50fdf" ]
```

Common image/container commands:

```bash
docker pull nginx:1.12-alpine-perl          # pull a specific tag
docker login docker-private.registry:1337   # authenticate to a private registry
docker run -p 80:80 nginx                    # run, mapping host:container ports
docker ps                                    # running containers
docker ps -a                                 # all containers, including stopped
docker stop <container-id>
docker rm <container-id>
```

---

## References

- Build command reference — <https://docs.docker.com/reference/cli/docker/buildx/build/>
- Dockerfile reference — <https://docs.docker.com/reference/dockerfile/>
