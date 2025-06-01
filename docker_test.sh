#!/bin/bash
# Build the Docker image
docker build -t ubuntu24-dot-files-test .
# Run the container, mounting current dir to /app
docker run -it --rm -v "$(pwd):/app" ubuntu24-dot-files-test
