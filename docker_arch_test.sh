#!/bin/bash
# Build the Arch Linux Docker image with no cache
docker build --no-cache -f Dockerfile.arch -t arch-dot-files-test .
# Run the container, mounting current dir to /app
docker run -it --rm -v "$(pwd):/app" arch-dot-files-test
