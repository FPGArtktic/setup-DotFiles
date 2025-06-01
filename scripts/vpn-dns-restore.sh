#!/bin/bash
# Script to restore original DNS settings after disconnecting from VPN

if [ -f /etc/resolv.conf.backup ]; then
  # Restore the backup
  cp /etc/resolv.conf.backup /etc/resolv.conf
  echo "Original DNS settings restored"
else
  echo "No backup found. Cannot restore DNS settings."
fi