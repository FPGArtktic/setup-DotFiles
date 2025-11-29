#!/bin/bash
# Build the Arch Linux Docker image
docker build -f Dockerfile.arch -t arch-dot-files-test .
# Run the container, mounting current dir to /app
docker run -it --rm -v "$(pwd):/app" arch-dot-files-test
