#!/bin/bash
# Build the Docker image
docker build -t ubuntu20-dot-files-test .
# Run the container, mounting current dir to /app
docker run -it --rm -v "$(pwd):/app" ubuntu20-dot-files-test
