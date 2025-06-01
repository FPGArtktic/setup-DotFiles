#!/bin/bash
# Script to configure DNS to <IP> when connected to VPN
# Add this to your VPN up scripts or run manually after connecting

# Backup current resolv.conf
cp /etc/resolv.conf /etc/resolv.conf.backup

# Set DNS to <IP>
echo "nameserver <IP>" > /etc/resolv.conf

echo "DNS set to <IP>"
echo "To restore original DNS settings run: vpn-dns-restore.sh"