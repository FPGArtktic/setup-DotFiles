#!/bin/bash
# Build the Docker image
docker build -t debian-bookworm-dot-files-test .
# Run the container, mounting current dir to /app
docker run -it --rm -v "$(pwd):/app" debian-bookworm-dot-files-test
