#!/usr/bin/env bash
#
# Usage:
#   curl -sSL https://<YOUR_SCRIPT_URL> | sudo bash
#
# This script:
#   1) Creates a non-root sudo user, copying root's SSH key to that user
#   2) Disables root login & password authentication for SSH
#   3) Installs and configures fail2ban
#   4) Sets up ufw firewall (allow SSH,HTTP,HTTPS)
#   5) Installs Docker + Docker Compose plugin
#   6) Enables unattended upgrades for security updates
#
set -e

#------------------------------------------------------------------------------------
# 0. Preliminary Checks: Must run as root or with sudo
#------------------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Please run as root (or with sudo). Exiting."
  exit 1
fi

echo "--------------------------------------------------------------------------------"
echo " This script will:"
echo "   - Create a new sudo user, copy root's authorized_keys"
echo "   - Disable root login & password auth in SSH"
echo "   - Install & configure fail2ban"
echo "   - Setup ufw firewall (ports 22,80,443 allowed)"
echo "   - Install Docker + Docker Compose plugin"
echo "   - Enable unattended upgrades for security updates"
echo "--------------------------------------------------------------------------------"
read -rp "Press ENTER to continue, or Ctrl+C to abort..."

#------------------------------------------------------------------------------------
# 1. Create a non-root sudo user, copy root's SSH keys
#------------------------------------------------------------------------------------
read -rp "Enter the new user name (e.g., 'myuser'): " NEW_USER
if [ -z "$NEW_USER" ]; then
  echo "No username entered. Exiting..."
  exit 1
fi

if id "$NEW_USER" &>/dev/null; then
  echo "User '$NEW_USER' already exists. Skipping creation."
else
  echo "Creating user '$NEW_USER'..."
  adduser --disabled-password --gecos "" "$NEW_USER"
  usermod -aG sudo "$NEW_USER"
fi

NEW_USER_HOME="/home/$NEW_USER"
NEW_USER_SSH="$NEW_USER_HOME/.ssh"

mkdir -p "$NEW_USER_SSH"
chmod 700 "$NEW_USER_SSH"
chown "$NEW_USER":"$NEW_USER" "$NEW_USER_SSH"

ROOT_AUTH_KEYS="/root/.ssh/authorized_keys"
if [ ! -f "$ROOT_AUTH_KEYS" ]; then
  echo "WARNING: /root/.ssh/authorized_keys not found! Make sure root has an SSH key."
  echo "Aborting to avoid locking you out."
  exit 1
fi

cp "$ROOT_AUTH_KEYS" "$NEW_USER_SSH/authorized_keys"
chown "$NEW_USER":"$NEW_USER" "$NEW_USER_SSH/authorized_keys"
chmod 600 "$NEW_USER_SSH/authorized_keys"

echo "User '$NEW_USER' created, and root's SSH key copied to $NEW_USER."

echo "Now let's set a password for '$NEW_USER' (this is *not* for SSH logins, since those are disabled)."
echo "This password is for 'sudo' usage or local console access."
passwd "$NEW_USER"

#------------------------------------------------------------------------------------
# 2. Harden SSH: Disable root login & password auth
#------------------------------------------------------------------------------------
echo "Hardening SSH (disabling root login & password auth)..."
sed -i 's/^#\?PermitRootLogin\s.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication\s.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?ChallengeResponseAuthentication\s.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config

systemctl restart ssh
echo "SSH hardened. Root login & password auth disabled."

#------------------------------------------------------------------------------------
# 3. Install & configure fail2ban
#------------------------------------------------------------------------------------
echo "Installing fail2ban..."
apt-get update -y
apt-get install -y fail2ban

cat <<EOF >/etc/fail2ban/jail.local
[sshd]
enabled = true
EOF

systemctl enable fail2ban
systemctl restart fail2ban

#------------------------------------------------------------------------------------
# 4. Setup ufw (firewall)
#------------------------------------------------------------------------------------
echo "Installing ufw..."
apt-get install -y ufw

echo "Allowing SSH(22), HTTP(80), HTTPS(443)..."
ufw allow 22
ufw allow 80
ufw allow 443

echo "Enabling ufw..."
ufw --force enable
ufw status

#------------------------------------------------------------------------------------
# 5. Install Docker + Docker Compose plugin
#------------------------------------------------------------------------------------
echo "Installing Docker using get.docker.com..."
curl -fsSL https://get.docker.com -o get-docker.sh
chmod +x get-docker.sh
./get-docker.sh

echo "Installing Docker Compose plugin..."
apt-get install -y docker-compose-plugin

echo "Adding '$NEW_USER' to the 'docker' group..."
usermod -aG docker "$NEW_USER"

#------------------------------------------------------------------------------------
# 6. Enable unattended upgrades
#------------------------------------------------------------------------------------
echo "Installing unattended-upgrades..."
apt-get install -y unattended-upgrades

echo "Enabling automatic security updates..."
cat <<EOF >/etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

# Optionally, remove unused dependencies automatically:
# echo 'Unattended-Upgrade::Remove-Unused-Dependencies "true";' >> /etc/apt/apt.conf.d/50unattended-upgrades

# To get email notifications, you'd configure mail. E.g.:
# echo 'Unattended-Upgrade::Mail "you@example.com";' >> /etc/apt/apt.conf.d/50unattended-upgrades

systemctl enable unattended-upgrades
systemctl start unattended-upgrades

#------------------------------------------------------------------------------------
# Done!
#------------------------------------------------------------------------------------
echo "------------------------------------------------------------------------------"
echo "Setup Complete!"
echo "  - New user '$NEW_USER' with sudo privileges (SSH key copied from root)."
echo "  - Root login & password-based SSH disabled."
echo "  - fail2ban installed & configured (SSH jail enabled)."
echo "  - ufw firewall active (ports 22,80,443 open)."
echo "  - Docker + Docker Compose installed."
echo "  - Unattended upgrades for security updates enabled."
echo "------------------------------------------------------------------------------"
echo "IMPORTANT: Open a new terminal and SSH in as '$NEW_USER' to test your login."
echo "           e.g., ssh $NEW_USER@<server_ip>"
echo "If successful, you can safely close your root session."
echo "You're ready to pull and run your Docker Compose projects. Enjoy!"
echo "------------------------------------------------------------------------------"
