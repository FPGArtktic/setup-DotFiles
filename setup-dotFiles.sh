#!/bin/bash
# Linux: DotFile postinstall Setup Script Ubuntu 24.04
# Version: 1.0.0
#
# Copyright (C) 2025 Mateusz Okulanis
# Email: FPGArtktic@outlook.com
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
DRY_RUN=false
VERBOSE=false
SKIP_SETUP=false
GIT_AUTHOR="Mateusz Okulanis"
GIT_EMAIL="FPGArtktic@outlook.com"
PROBED_OS=""

usage () {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --dry-run               Perform a dry run without making changes"
    echo "  --verbose, -v           Enable verbose output"
    echo "  --script-gen-only       Generate the script without executing it"
    echo "  --yes, -y               Skip all prompts and proceed with default actions"
    echo "  --help                  Show this help message"
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --yes|-y)
                SKIP_SETUP=true
                shift
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
}

welcome () {
    echo "Welcome to the DotFile postinstall setup script for Ubuntu 24.04!"
    echo "This script will help you set up your system after installing the DotFiles."
    echo "You can customize the setup by passing command line arguments."
    echo "For more information, run the script with --help."
}

install_bashrc() {
    if $SKIP_SETUP; then
        echo > /dev/null
    else
    while true; do
        echo "Do you want to install the bashrc file? ([Y]/n)"
        read -r answer
        if [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]; then
            break
        elif [[ "$answer" =~ ^[Nn]$ ]]; then
            if $VERBOSE; then
                echo "Skipping bashrc installation."
            fi
            return
        else
            echo "Please answer Y (yes) or N (no)."
        fi
    done
    fi

    echo "Installing bashrc..."
    cat ./bashrc >> ~/.bashrc
}

install_git_rules() {
    if $SKIP_SETUP; then
        echo > /dev/null
    else
    while true; do
        echo "Git rules will be installed globally."
        echo "git config --global core.fileMode false"
        echo "git config --global user.name $GIT_AUTHOR"
        echo "git config --global user.email $GIT_EMAIL"
        echo "Do you want to these install git rules ([Y]/n)"
        read -r answer
        if [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]; then
            break
        elif [[ "$answer" =~ ^[Nn]$ ]]; then
            if $VERBOSE; then
                echo "Skipping git rules installation."
            fi
            return
        else
            echo "Please answer Y (yes) or N (no)."
        fi

    done
    fi
    git config --global core.fileMode false
    git config --global user.name "$GIT_AUTHOR"
    git config --global user.email "$GIT_EMAIL"
    echo "Git rules installed successfully."
    echo "Current git configuration:"
    echo "---------------------------------"
    git config --global --list
    echo "---------------------------------"
}

install_ram_disk() {
    if $SKIP_SETUP; then
        echo > /dev/null
    else
    while true; do
        echo "Do you want to create a RAM disk? ([Y]/n)"
        read -r answer
        if [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]; then
            break
        elif [[ "$answer" =~ ^[Nn]$ ]]; then
            if $VERBOSE; then
                echo "Skipping RAM disk creation."
            fi
            return
        else
            echo "Please answer Y (yes) or N (no)."
        fi
    done
    fi
    echo "Creating RAM disk..."
    ln -s /dev/shm/ ~/RAMDISC
}

install_fzf() {
    if $SKIP_SETUP; then
        echo > /dev/null
    else
    while true; do
        echo "Do you want to these install fzf ([Y]/n)"
        read -r answer
        if [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]; then
            break
        elif [[ "$answer" =~ ^[Nn]$ ]]; then
            if $VERBOSE; then
                echo "Skipping fzf installation."
            fi
            return
        else
            echo "Please answer Y (yes) or N (no)."
        fi
    done
    fi
    echo "Installing fzf..."
    git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
    $HOME/.fzf/install --all
    cat ./fzf.bash > ~/.fzf.bash
    }

install_ubuntu_update_and_upgrade() {
    if $SKIP_SETUP; then
        echo > /dev/null
    else
        echo "Updating ubuntu and upgrade package lists..."
        if $DRY_RUN; then
            echo "Dry run: Package lists would be updated here."
        else
            sudo apt-get -y update
            sudo apt-get -y full-upgrade
        fi
    fi
}

install_arch_update_and_upgrade() {
    if $SKIP_SETUP; then
        echo > /dev/null
    else
        echo "Updating arch and upgrade package lists..."
        if $DRY_RUN; then
            echo "Dry run: Package lists would be updated here."
        else
            sudo pacman -Syu --noconfirm
            sudo yay -Syu --noconfirm
        fi
    fi
}

install_apt_packages() {
    if $SKIP_SETUP; then
        echo > /dev/null
    else
    while true; do
        echo "Apt install"
        echo "Note: This will install all packages listed in the script."
        cat apt-apps.txt
        echo "Do you want to these install apt packages? ([Y]/n)"
        read -r answer
        if [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]; then
            break
        elif [[ "$answer" =~ ^[Nn]$ ]]; then
            if $VERBOSE; then
                echo "Skipping apt installation."
            fi
            return
        else
            echo "Please answer Y (yes) or N (no)."
        fi
    done
    fi
    echo "Installing apt packages..."
    if $DRY_RUN; then
        echo "Dry run: Apt packages installation would be performed here."
        echo "apt-get install -y $(cat apt-apps.txt)"
        return
    else
        if $VERBOSE; then
            echo "Apt packages installed successfully."
        fi
    fi
    sudo apt-get install -y $(cat apt-apps.txt)
}

install_yay_packages() {
    if $SKIP_SETUP; then
        echo > /dev/null
    else
    while true; do
        echo "Yay install"
        echo "Note: This will install all packages listed in the script."
        cat yay-apps.txt
        echo "Do you want to these install yay packages? ([Y]/n)"
        read -r answer
        if [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]; then
            break
        elif [[ "$answer" =~ ^[Nn]$ ]]; then
            if $VERBOSE; then
                echo "Skipping yay installation."
            fi
            return
        else
            echo "Please answer Y (yes) or N (no)."
        fi
    done
    fi
    echo "Installing yay packages..."
    if $DRY_RUN; then
        echo "Dry run: Yay packages installation would be performed here."
        echo "yay -S --noconfirm $(cat yay-apps.txt)"
        return
    else
        if $VERBOSE; then
            echo "Yay packages installed successfully."
        fi
    fi
    yay -S --noconfirm $(cat yay-apps.txt)
}

install_ubuntu_docker() {
    if $SKIP_SETUP; then
        echo > /dev/null
    else
    while true; do
        echo "Do you want to install Docker? ([Y]/n)"
        read -r answer
        if [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]; then
            break
        elif [[ "$answer" =~ ^[Nn]$ ]]; then
            if $VERBOSE; then
                echo "Skipping Docker installation."
            fi
            return
        else
            echo "Please answer Y (yes) or N (no)."
        fi
    done
    fi

    if $DRY_RUN; then
        echo "Dry run: Docker installation would be performed here."
    else
        echo "Installing Docker..."
        # Add Docker's official GPG key:
        sudo apt-get update
        sudo apt-get install ca-certificates curl
        sudo install -m 0755 -d /etc/apt/keyrings
        sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc
        # Add the repository to Apt sources:
        echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update
        sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        sudo docker run hello-world
        sudo groupadd docker
        sudo usermod -aG docker $USER
        sudo systemctl start docker.service
        sudo systemctl start containerd.service
        sudo systemctl enable docker.service
        sudo systemctl enable containerd.service
    fi
}

install_tmux() {
    if $SKIP_SETUP; then
        echo > /dev/null
    else
    while true; do
        echo "Do you want to install TMUX? ([Y]/n)"
        read -r answer
        if [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]; then
            break
        elif [[ "$answer" =~ ^[Nn]$ ]]; then
            if $VERBOSE; then
                echo "Skipping TMUX installation."
            fi
            return
        else
            echo "Please answer Y (yes) or N (no)."
        fi
    done
    fi
    if $DRY_RUN; then
        echo "Dry run: TMUX installation would be performed here."
    else
        cp ./tmux.conf ~/.tmux.conf
        echo "TMUX config installed successfully."
    fi
}

install_tailscale() {
    if $SKIP_SETUP; then
        echo > /dev/null
    else
    while true; do
        echo "Do you want to install tailscale? ([Y]/n)"
        read -r answer
        if [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]; then
            break
        elif [[ "$answer" =~ ^[Nn]$ ]]; then
            if $VERBOSE; then
                echo "Skipping tailscale installation."
            fi
            return
        else
            echo "Please answer Y (yes) or N (no)."
        fi
    done
    fi
    if $DRY_RUN; then
        echo "Dry run: tailscale installation would be performed here."
    else
        curl -fsSL https://tailscale.com/install.sh | sudo sh
    fi
}

install_sshkey() {
    if $SKIP_SETUP; then
        echo > /dev/null
    else
    while true; do
        echo "Do you want to install ssh keygen? ([Y]/n)"
        read -r answer
        if [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]; then
            break
        elif [[ "$answer" =~ ^[Nn]$ ]]; then
            if $VERBOSE; then
                echo "Skipping ssh keygen installation."
            fi
            return
        else
            echo "Please answer Y (yes) or N (no)."
        fi
    done
    fi
    if $DRY_RUN; then
        echo "Dry run: ssh keygen would be performed here."
    else
        if $SKIP_SETUP; then
            echo "Generating SSH key..."
            ssh-keygen -t ed25519 -C "$GIT_EMAIL"
            echo "SSH key generated successfully."
        else 
            echo "Generating SSH key..."
            ssh-keygen -t ed25519 -C "$GIT_EMAIL"
            echo "SSH key generated successfully."
            echo "Add the public key to your GitHub account:"
            echo "cat ~/.ssh/id_ed25519.pub"
            echo "Remember to add the private key to your SSH agent:"
            echo "ssh-add ~/.ssh/id_ed25519"
        fi
    fi
}

install_ubuntu_vscode() {
    if $SKIP_SETUP; then
        echo > /dev/null
    else
    while true; do
        echo "Do you want to install vs code? ([Y]/n)"
        read -r answer
        if [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]; then
            break
        elif [[ "$answer" =~ ^[Nn]$ ]]; then
            if $VERBOSE; then
                echo "Skipping vs code installation."
            fi
            return
        else
            echo "Please answer Y (yes) or N (no)."
        fi
    done
    fi
    if $DRY_RUN; then
        echo "Dry run: vscode would be performed here."
    else
        echo "Installing Visual Studio Code..."
        sudo apt-get install wget gpg
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
        sudo install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
        echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" |sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
        rm -f packages.microsoft.gpg
        sudo apt install apt-transport-https
        sudo apt update
        sudo apt install code # or code-insiders
        echo "Visual Studio Code installed successfully."
    fi
}

setup_cli_ai_clients() {
    if $SKIP_SETUP; then
        echo > /dev/null
    else
    while true; do
        echo "Do you want to install CLI AI clients? ([Y]/n)"
        read -r answer
        if [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]; then
            break
        elif [[ "$answer" =~ ^[Nn]$ ]]; then
            if $VERBOSE; then
                echo "Skipping CLI AI clients installation."
            fi
            return
        else
            echo "Please answer Y (yes) or N (no)."
        fi
    done
    fi
    if $DRY_RUN; then
        echo "Dry run: CLI AI clients installation would be performed here."
    else
        echo "Installing CLI AI clients..."
        sudo npm install -g @google/gemini-cli@latest
        sudo npm install -g @github/copilot
        echo "CLI AI clients installed successfully."
    fi
}

ubuntu_post_installation() {
    if $SKIP_SETUP; then
        echo > /dev/null
    else
        echo "Post-installation tasks completed."
        sudo apt-get autoremove -y
        sudo apt-get autoclean -y
        echo "System cleanup completed."
        echo "Please restart your terminal or run 'source ~/.bashrc' to apply changes."
    fi
}

arch_post_installation() {
    if $SKIP_SETUP; then
        echo > /dev/null
    else
        echo "Post-installation tasks completed."
        sudo pacman -Rns $(pacman -Qtdq) --noconfirm
        yay -Yc --noconfirm
        echo "System cleanup completed."
        echo "Please restart your terminal or run 'source ~/.bashrc' to apply changes."
    fi
}

my_zsh_install() {
    if $SKIP_SETUP; then
        echo > /dev/null
    else
    while true; do
        echo "Do you want to install Oh My Zsh? ([Y]/n)"
        read -r answer
        if [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]; then
            break
        elif [[ "$answer" =~ ^[Nn]$ ]]; then
            if $VERBOSE; then
                echo "Skipping Oh My Zsh installation."
            fi
            return
        else
            echo "Please answer Y (yes) or N (no)."
        fi
    done
    fi
    if $DRY_RUN; then
        echo "Dry run: Oh My Zsh installation would be performed here."
    else
        echo "Installing Oh My Zsh..."
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        ln -s ~/git/ohmyzsh-mtsh-theme/mtsh.zsh-theme ~/.oh-my-zsh/custom/themes/mtsh.zsh-theme
        sed -i 's/ZSH_THEME=".*"/ZSH_THEME="mtsh"/' ~/.zshrc
        echo "Oh My Zsh installed successfully."
        #enable fzf plugin
        sed -i 's/plugins=(git)/plugins=(git fzf)/' ~/.zshrc
        #source bash history to zsh
        echo "source ~/.fzf.bash" >> ~/.zshrc
        sudo chsh -s $(which zsh) $USER
    fi
}

add_cron_jobs () {
    if $SKIP_SETUP; then
        echo > /dev/null
    else
    while true; do
        echo "Do you want to add cron jobs? ([Y]/n)"
        read -r answer
        if [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]; then
            break
        elif [[ "$answer" =~ ^[Nn]$ ]]; then
            if $VERBOSE; then
                echo "Skipping cron jobs addition."
            fi
            return
        else
            echo "Please answer Y (yes) or N (no)."
        fi
    done
    fi
    if $DRY_RUN; then
        echo "Dry run: Cron jobs addition would be performed here."
    else
        echo "Adding cron jobs..."
        (crontab -l 2>/dev/null; echo "*/12 * * * * ~/git/AutoGit-o-Matic/autogit-o-matic.sh --log-file /dev/shm/autogitomatic.log") | crontab -
        (crontab -l 2>/dev/null; echo "* */4 * * * rm  /dev/shm/autogitomatic.log") | crontab -
        echo "Cron jobs added successfully."
    fi
}

git_dir_and_clone() {
    if $SKIP_SETUP; then
        echo > /dev/null
        return
    fi
    while true; do
        echo "Do you want to clone git repositories? ([Y]/n)"
        read -r answer
        if [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]; then
            break
        elif [[ "$answer" =~ ^[Nn]$ ]]; then
            if $VERBOSE; then
                echo "Skipping git repositories cloning."
            fi
            return
        else
            echo "Please answer Y (yes) or N (no)."
        fi
    done
    if $DRY_RUN; then
        echo "Dry run: git repositories cloning would be performed here."
    else
        echo "Cloning git repositories..."
        mkdir ~/git
        git clone git@github.com:FPGArtktic/GnuRAMage.git ~/git/GnuRAMage
        git clone git@github.com:FPGArtktic/AutoGit-o-Matic.git ~/git/AutoGit-o-Matic
        git clone git@github.com:FPGArtktic/setup-DotFiles.git ~/git/setup-DotFiles
        git clone git@github.com:FPGArtktic/ohmyzsh-mtsh-theme.git ~/git/ohmyzsh-mtsh-theme
        git clone git@github.com:FPGArtktic/FPGArtktic.github.io.git ~/git/FPGArtktic.github.io
        cd ~
        cp ~/setup-DotFiles/autogit-o-matic.ini ~/git/AutoGit-o-Matic/autogit-o-matic.ini
    fi
}



install_yay() {
    if $SKIP_SETUP; then
        echo > /dev/null
    else
    while true; do
        echo "Do you want to install yay? ([Y]/n)"
        read -r answer
        if [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]; then
            break
        elif [[ "$answer" =~ ^[Nn]$ ]]; then
            if $VERBOSE; then
                echo "Skipping yay installation."
            fi
            return
        else
            echo "Please answer Y (yes) or N (no)."
        fi
    done
    fi
    if $DRY_RUN; then
        echo "Dry run: yay installation would be performed here."
    else
        sudo pacman -S --needed git base-devel
        git clone https://aur.archlinux.org/yay-bin.git
        cd yay-bin
        makepkg -si
        cd -
        yay -Y --gendb
        yay -Syu --devel
        yay -Y --devel --save

    fi
}

install_virtualbox_configuration() {
    if $SKIP_SETUP; then
        echo > /dev/null
    else
    while true; do
        echo "Do you want to install VirtualBox configuration?  ([Y]/n)"
        read -r answer
        if [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]; then
            break
        elif [[ "$answer" =~ ^[Nn]$ ]]; then
            if $VERBOSE; then
                echo "Skipping VirtualBox installation."
            fi
            return
        else
            echo "Please answer Y (yes) or N (no)."
        fi
    done
    fi

    if $DRY_RUN; then
        echo "Dry run: VirtualBox installation would be performed here."
    else
        echo "Installing VirtualBox configuration..."
        sudo usermod -aG vboxusers  $USER
    fi
}


probe_os() {
    if grep -q '^ID=ubuntu$' /etc/os-release && grep -q '^VERSION_ID="24' /etc/os-release; then
        echo "Ubuntu 24.x"
        PROBED_OS="ubuntu24"
    elif grep -q '^ID=arch$' /etc/os-release; then
        echo "Arch Linux"
        PROBED_OS="arch"
    else
        echo "Only Ubuntu 24.x and Arch Linux is supported by this script."
        PROBED_OS="unsupported"
    fi
}

main() {
    # Parse command line arguments
    parse_arguments "$@"
    if $VERBOSE; then
        welcome 
    fi
    probe_os
    if [ "$PROBED_OS" = "unsupported" ]; then
        echo "Exiting setup due to unsupported OS."
        exit 1
    fi
    if [ "$PROBED_OS" = "ubuntu24" ]; then
        echo "Proceeding with Ubuntu 24.04 setup..."
            install_ubuntu_update_and_upgrade
            install_bashrc
            install_apt_packages
            install_sshkey
            install_ubuntu_vscode
            install_ubuntu_docker
            install_fzf
            install_ram_disk
            install_tmux
            install_git_rules
            install_tailscale
            git_dir_and_clone
            add_cron_jobs
            my_zsh_install
            setup_cli_ai_clients
            install_virtualbox_configuration
            ubuntu_post_installation
    fi
    if [ "$PROBED_OS" = "arch" ]; then
        echo "Arch Linux detected. Running Arch-specific setup..."
        install_arch_update_and_upgrade
        install_yay
        install_bashrc
        install_yay_packages
        install_sshkey
        install_fzf
        install_ram_disk
        install_tmux
        install_git_rules
        install_tailscale
        git_dir_and_clone
        add_cron_jobs
        oh_my_zsh_install
        setup_cli_ai_clients
        install_virtualbox_configuration
        arch_post_installation
    fi

}

# Start the program
main "$@"

# Exit the script