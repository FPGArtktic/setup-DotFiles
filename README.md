# setup-dotFiles My personal dotfiles and configuration scripts for Ubuntu 24.04

<p align="center">
  <img src="img/logo.jpeg" alt="setup-dotFiles" width="500"/>
</p>

**License**: GNU GPLv3

## Overview

This repository contains a comprehensive set of dotfiles and configuration scripts for setting up an Ubuntu 24.04 environment. It automates the installation and configuration of various tools, packages, and settings to quickly set up a consistent development environment.

## Why this project?

I was tired of running the same configuration scripts on each of my computers, so I decided to automate the process and collect everything in one place.

## Features

- Automatic installation of essential packages (git, build-essential, curl, etc.)
- Configuration of git global settings
- Installation and configuration of productivity tools (tmux, fzf, etc.)
- Docker installation and configuration
- RAM disk setup
- Custom bashrc configuration

## Docker Test Environment

This repository includes a Docker-based test environment that allows you to test the dotfiles and scripts in an isolated Ubuntu 24.04 container without affecting your host system.

### Prerequisites

- Docker installed on your host system

### Using the Docker Test Environment

1. Clone this repository:
   ```bash
   git clone https://github.com/.../dotfiles.git
   cd dotfiles
   ```

2. Run the Docker test script:
   ```bash
   ./docker_test.sh
   ```
   or
   ```bash
   ./run.sh
   ```

This will:
- Build a Docker image based on Ubuntu 24.04
- Create a container with sudo privileges
- Mount the current directory to /app in the container
- Start an interactive bash session

### Manual Steps in Docker Container

When inside the Docker container:

1. You'll be logged in as the user `user` by default
2. The password for `user` is `user`
3. You have sudo privileges without needing a password
4. The dotfiles repository is mounted at `/app`

To test the dotfiles setup script:
```bash
cd /app
./setup-dotFile.sh
```

You can use various flags with the setup script:
- `--dry-run`: Show what would be done without making changes
- `-v` or `--verbose`: Enable verbose output
- `-y` or `--yes`: Skip all prompts and proceed with default actions
- `--help`: Show help message

## Installation on Real System

To install these dotfiles on your actual Ubuntu 24.04 system:

```bash
git clone https://github.com/username/dotfiles.git
cd dotfiles
./setup-dotFile.sh
```

## Components

- **bashrc**: Custom bash configuration
- **tmux.conf**: TMUX configuration file
- **apt-apps.txt**: List of packages to be installed
- **fzf.bash**: FZF (Fuzzy Finder) configuration
- **scripts/**: Various utility scripts (for my purposes)
  - VPN DNS configuration tools
- **code-templates/hooks/**: Git hooks templates

## Author

Mateusz Okulanis  
Email: FPGArtktic@outlook.com

## License

This project is licensed under the GNU General Public License v3.0 - see the comments in the script files for details.

Copyright (C) 2025 Mateusz Okulanis

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
