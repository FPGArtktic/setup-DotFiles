#!/bin/bash
# Build the Ubuntu Docker image
docker build -f Dockerfile.ubuntu -t ubuntu-dot-files-test .
# Run the container, mounting current dir to /app
docker run -it --rm -v "$(pwd):/app" ubuntu-dot-files-test
