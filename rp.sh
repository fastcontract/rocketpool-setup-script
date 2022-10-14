#!/bin/bash

#this script basically just executes the commands outlined here:
#https://docs.rocketpool.net/guides/node/local/prepare-pc.html
#https://docs.rocketpool.net/guides/node/securing-your-node.html#assumptions-in-this-guide
#https://docs.rocketpool.net/guides/node/docker.html#downloading-the-rocket-pool-cli
#with the addition of tailscale for extra security
#this has been tested on a clean install of Ubuntu 22.04.1 on an intel nuc8i5
#it also adds 3 helpful aliases to the users bashrc file and asks if the user would like to use it to install rocketpool


GREEN='\033[0;36m'
RED='\033[0;31m'
PURP='\033[0;35m'
NC='\033[0m' # No Color
DIVIDER='###############################'

set -e
set -o pipefail

fail() {
     MESSAGE=$1
     >&2 echo -e "\n${RED}**ERROR**\n$MESSAGE${NC}"
     exit 1 
}

echo -e "${GREEN}${DIVIDER}\nupdating all installed software\nthis may take some time on a fresh install\n${DIVIDER}${NC}";
sudo apt update && sudo apt -y dist-upgrade && sudo apt -y autoremove;

echo -e "${GREEN}${DIVIDER}\ninstalling SSH server\n${DIVIDER}${NC}";
sudo apt install -y openssh-server net-tools || fail "openssh-server or net-tools install step failure.";

echo -e "${GREEN}${DIVIDER}\ngenerating SSH key file.\nPICK A SECURE PASSWORD for key\nit will be copied to your Documents\nfor use in putty.\n${DIVIDER}${RED}";
read -p "Enter the email you would like to use for the SSH key and hit Enter.    " EMAIL
echo -e "${NC}";
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "${EMAIL}" || fail "ssh-keygen has failed.";
sudo mv ~/.ssh/id_ed25519 ~/Documents/key.ppk || fail "failed to move private key to Documents";
sudo chmod 777 ~/Documents/key.ppk;
sudo cp ~/.ssh/id_ed25519.pub ~/.ssh/authorized_keys || fail "failed  to add public key to authorized_keys.";
echo -e "${GREEN}${DIVIDER}\nThis will now pause for you to copy the SSH private key to a usb drive.\n${DIVIDER}${NC}";
echo -e "${RED}";
read -p "Press ENTER to open the location of your private SSH key and copy or move it to another location. KEEP IT SAFE.";
echo -e "${GREEN}";

nautilus --browser ~/Documents &>/dev/null&
while true; do
    read -p "Have you copied your SSH key (y/n)?" yn
    case $yn in
        [Yy]* ) echo -e "${RED}Deleting private key${GREEN}";rm -rf ~/Documents/key.ppk || fail "Failed to remove SSH private key. Check your Documents folder.";
        break;;
        * ) echo -e "${RED}Please copy or move it, as it will be deleted after confirming.${GREEN}";;
    esac
done;

echo -e "${GREEN}${DIVIDER}\ninstalling google 2 factor authentication\n${DIVIDER}${NC}";
sudo apt install -y libpam-google-authenticator || fail "google authenticator install step failure.";

echo -e "${GREEN}${DIVIDER}\ninstalling tailscale\n${DIVIDER}${NC}";
sudo apt install -y curl || fail "failed to install curl.";
curl -fsSL https://tailscale.com/install.sh | sh;

echo -e "${GREEN}${DIVIDER}\nactivating tailscale\nctrl click this link\nand login to continue\n${DIVIDER}${NC}";
sudo tailscale up || fail "tailscale launch failure.";

echo -e "${GREEN}${DIVIDER}\ngenerating google 2fa\nscan the qr code into your 2fa app\nand keep the backup codes\nsomeplace safe.\n${DIVIDER}${NC}";
google-authenticator -t -f -d -r 3 -R 30 -w 3 || fail "google authenticator launch failure.";
echo -e "${RED}";
read -p "Press ENTER once you have scanned the QR code with your 2fa app and backed up the scratch codes. You may need to resize the window or use the secret key if your resolution is too small.";
echo -e "${NC}";
sudo sed -i '33,34s/PermitRootLogin yes/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config || fail "sshd_config file modification failure.";
sudo sed -i '41,42s/#AuthorizedKeysFile/AuthorizedKeysFile/' /etc/ssh/sshd_config || fail "sshd_config file modification failure.";
sudo sed -i '57,58s/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config || fail "sshd_config file modification failure.";sudo sed -i '62s/KbdInteractiveAuthentication no/KbdInteractiveAuthentication yes/' /etc/ssh/sshd_config || fail "sshd_config file modification failure.";
sudo sed -i '63s/ChallengeResponseAuthentication no/ChallengeResponseAuthentication yes/' /etc/ssh/sshd_config || fail "sshd_config file modification failure.";
sudo tee -a /etc/ssh/sshd_config<<<"AuthenticationMethods publickey,keyboard-interactive" || fail "sshd_config file modification failure.";
sudo tee -a /etc/pam.d/sshd<<<"auth required pam_google_authenticator.so" || fail "pam.d/sshd file modification failure.";
sudo sed -i '4s/@include common-auth/# @include common-auth/' /etc/pam.d/sshd || fail "pam.d/sshd file modification failure.";

echo -e "${GREEN}${DIVIDER}\nactivating automatic security updates\n${DIVIDER}${NC}";
sudo apt install -y unattended-upgrades update-notifier-common || fail "unattended upgrade installation failure.";
sudo tee /etc/apt/apt.conf.d/20auto-upgrades <<<"APT::Periodic::Update-Package-Lists \"1\";
APT::Periodic::Unattended-Upgrade \"1\";
APT::Periodic::AutocleanInterval \"7\";
Unattended-Upgrade::Remove-Unused-Dependencies \"true\";
Unattended-Upgrade::Remove-New-Unused-Dependencies \"true\";
Unattended-Upgrade::Automatic-Reboot \"true\";
Unattended-Upgrade::Automatic-Reboot-Time \"02:00\";" 
sudo systemctl restart unattended-upgrades || fail "failed to restart unattended upgrades.";

echo -e "${GREEN}${DIVIDER}\nsetting up the UFW firewall\n${DIVIDER}${NC}";
sudo ufw default deny incoming comment 'Deny all incoming traffic' || fail "failed to set ufw firewall rule.";
sudo ufw default allow outgoing || fail "failed to set ufw firewall rule.";
sudo ufw allow "22/tcp" comment 'Allow SSH' || fail "failed to set ufw firewall rule.";
sudo ufw allow in on tailscale0 || fail "failed to set ufw firewall rule.";
sudo ufw allow 41641/udp || fail "failed to set ufw firewall rule.";
sudo ufw allow 30303/tcp comment 'Execution client port, standardized by Rocket Pool' || fail "failed to set ufw firewall rule.";
sudo ufw allow 30303/udp comment 'Execution client port, standardized by Rocket Pool' || fail "failed to set ufw firewall rule.";
sudo ufw allow 9001/tcp comment 'Consensus client port, standardized by Rocket Pool' || fail "failed to set ufw firewall rule.";
sudo ufw allow 9001/udp comment 'Consensus client port, standardized by Rocket Pool' || fail "failed to set ufw firewall rule.";
sudo ufw allow 18550 comment 'mev port' || fail "failed to set ufw firewall rule.";
sudo ufw enable || fail "failed to enable ufw firewall.";

echo -e "${GREEN}${DIVIDER}\ninstalling fail2ban bruteforce protection for SSH\n${DIVIDER}${NC}";
sudo apt install -y fail2ban || fail "failed to install fail2ban.";
sudo tee /etc/fail2ban/jail.d/ssh.local <<<"[sshd]
enabled = true
banaction = ufw
port = 22
filter = sshd
logpath = %(sshd_log)s
maxretry = 10"
sudo systemctl restart fail2ban || fail "failed to start fail2ban.";
sudo systemctl restart sshd || fail "failed to restart sshd.";

echo -e "${GREEN}${DIVIDER}\nsecuring your node complete!\nadding some helpful aliases\n${DIVIDER}${NC}";
sudo echo "alias osupdate='sudo apt update && sudo apt -y dist-upgrade && sudo apt -y autoremove'" >> ~/.bashrc || fail "failed to add osupdate alias.";
sudo echo "alias rpupdate='rocketpool service stop && sudo apt update && sudo apt -y dist-upgrade && sudo apt -y autoremove && sudo wget https://github.com/rocket-pool/smartnode-install/releases/latest/download/rocketpool-cli-linux-amd64 -O ~/bin/rocketpool && rocketpool service install -d && rocketpool service start'" >> ~/.bashrc || fail "failed to add rpupdate alias.";
sudo echo "alias rpstatus='echo \"###########################\";rocketpool node status;echo \"###########################\";rocketpool node sync;echo \"###########################\";rocketpool service status;echo \"###########################\";rocketpool service version;echo \"###########################\";rocketpool minipool status'" >> ~/.bashrc || fail "failed to add rpstatus alias.";
sudo echo "alias claim='rocketpool node claim-rewards'" >> ~/.bashrc || fail "failed to add claim alias.";
source ~/.bashrc || fail "failed to source bashrc.";

echo -e "\naliases installed.\nyou can type ${GREEN}osupdate${NC} in a terminal to update all software\nor type ${GREEN}rpupdate${NC} to just update rocketpool\nor type ${GREEN}rpstatus${NC} to get information about your node\nor type ${GREEN}claim${NC} when you want to claim your rpl rewards.\n${GREEN}";

echo -e "${DIVIDER}\ninstalling rocketpool\n${DIVIDER}${NC}";
sudo mkdir -p ~/bin || fail "failed to make bin dir.";
sudo wget https://github.com/rocket-pool/smartnode-install/releases/latest/download/rocketpool-cli-linux-amd64 -O ~/bin/rocketpool || fail "failed to get rocketpool install files.";
sudo chmod +x ~/bin/rocketpool;
source ~/.profile;
rocketpool service install -y || fail "failed to install rocketpool.";
echo -e "${PURP}${DIVIDER}\nrocketpool has been installed!\nyou can now restart this machine, disconnect your monitor, and connect through ssh.\n${DIVIDER}";
