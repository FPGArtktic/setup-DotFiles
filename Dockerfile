FROM ubuntu:22.04

# Install sudo and create a user with sudo privileges
RUN apt-get update && \
    apt-get install -y sudo && \
    useradd -m user && \
    echo 'user:user' | chpasswd && \
    usermod -aG sudo user && \
    echo 'user ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

WORKDIR /app
USER user
CMD ["bash"]
