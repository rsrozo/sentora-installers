#!/usr/bin/env bash

# Official Sentora Automated Installation Script
# =============================================
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Supported Operating Systems: 
# Ubuntu server 24.04 
# Debian 12.*
# 32bit and 64bit
#
# Contributions from:
#
#   Anthony DeBeaulieu (anthony.d@sentora.org)
#   TGagtes 
#   Pascal Peyremorte (ppeyremorte@sentora.org)
#   Mehdi Blagui
#   Kevin Andrews (kevin@zvps.uk)
#
#   and all those who participated to this and to previous installers.
#   Thanks to all.

## 
# SENTORA_CORE/INSTALLER_VERSION
# master - latest unstable
# 2.1.0 - example stable tag
##

SENTORA_INSTALLER_VERSION="master"
SENTORA_CORE_VERSION="master"

PANEL_PATH="/etc/sentora"
PANEL_DATA="/var/sentora"
PANEL_CONF="/etc/sentora/configs"
PANEL_UPGRADE=false

#--- Display the 'welcome' splash/user warning info..
echo ""
echo "############################################################"
echo "#  Welcome to the Official Sentora Installer v.$SENTORA_INSTALLER_VERSION  #"
echo "############################################################"

echo -e "\nChecking that minimal requirements are ok"

# Ensure the OS is compatible with the launcher
# leave CentOS code..
if [ -f /etc/centos-release ]; then
    OS="CentOs"
    VERFULL=$(sed 's/^.*release //;s/ (Fin.*$//' /etc/centos-release)
    VER=${VERFULL:0:1} # return 8
elif [ -f /etc/lsb-release ]; then
    OS=$(grep DISTRIB_ID /etc/lsb-release | sed 's/^.*=//')
    VER=$(grep DISTRIB_RELEASE /etc/lsb-release | sed 's/^.*=//')
elif [ -f /etc/os-release ]; then
    OS=$(grep -w ID /etc/os-release | sed 's/^.*=//')
    VER=$(grep VERSION_ID /etc/os-release | sed 's/^.*"\(.*\)"/\1/')
 else
    OS=$(uname -s)
    VER=$(uname -r)
fi
ARCH=$(uname -m)

echo "Detected : $OS  $VER  $ARCH"

if [[ "$OS" = "Ubuntu" && ( "$VER" = "24.04" ) ||
	  "$OS" = "debian" && ( "$VER" = "12" ) ]] ; then
    echo "Ok."
else
    echo "Sorry, this OS is not supported by Sentora." 
    exit 1
fi

# Centos uses repo directory that depends of architecture. Ensure it is compatible
# leave CentOS code..
if [[ "$OS" = "CentOs" ]] ; then
    if [[ "$ARCH" == "i386" || "$ARCH" == "i486" || "$ARCH" == "i586" || "$ARCH" == "i686" ]]; then
        ARCH="i386"
    elif [[ "$ARCH" != "x86_64" ]]; then
        echo "Unexpected architecture name was returned ($ARCH ). :-("
        echo "The installer have been designed for i[3-6]8- and x86_64' architectures. If you"
        echo " think it may work on your, please report it to the Sentora forum or bugtracker."
        exit 1
    fi
fi

# Check if the user is 'root' before allowing installation to commence
if [ $UID -ne 0 ]; then
    echo "Install failed: you must be logged in as 'root' to install."
    echo "Use command 'sudo -i', then enter root password and then try again."
    exit 1
fi

# Check for some common control panels that we know will affect the installation/operating of Sentora.
if [ -e /usr/local/cpanel ] || [ -e /usr/local/directadmin ] || [ -e /usr/local/solusvm/www ] || [ -e /usr/local/home/admispconfig ] || [ -e /usr/local/lxlabs/kloxo ] ; then
    echo "It appears that a control panel is already installed on your server; This installer"
    echo "is designed to install and configure Sentora on a clean OS installation only."
    echo -e "\nPlease re-install your OS before attempting to install using this script."
    exit 1
fi

# Check for some common packages that we know will affect the installation/operating of Sentora.
if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
	if [[ "$VER" = "24.04" ]]; then

		PACKAGE_INSTALLER="apt-get -yqq install"
		PACKAGE_REMOVER="apt-get -yqq remove"
	
		inst() {
		   dpkg -l "$1" 2> /dev/null | grep '^ii' &> /dev/null
		}
		
		DB_PCKG="mysql-server"
		HTTP_PCKG="apache2"
		PHP_PCKG="apache2-mod-php8"
		BIND_PCKG="bind9"

	elif [[ "$VER" = "12" ]]; then
	
		PACKAGE_INSTALLER="apt-get -yqq install"
		PACKAGE_REMOVER="apt-get -yqq remove"
	
		inst() {
		   dpkg -l "$1" 2> /dev/null | grep '^ii' &> /dev/null
		}
		
		DB_PCKG="default-mysql-server"
		HTTP_PCKG="apache2"
		PHP_PCKG="apache2-mod-php8"
		BIND_PCKG="bind9"
	
	fi
fi
  
# Note : Postfix is installed by default on centos netinstall / minimum install.
# The installer seems to work fine even if Postfix is already installed.
# -> The check of postfix is removed, but this comment remains to remember
# only check for sentora installed systems zpanel can now upgrade using this script
if [ -L "/etc/zpanel" ] && [ -d "/etc/zpanel"  ]; then
    pkginst="n"
    pkginstlist=""
    for package in "$DB_PCKG" "dovecot-mysql" "$HTTP_PCKG" "$PHP_PCKG" "proftpd" "$BIND_PCKG" ; do
        if (inst "$package"); then
            pkginst="y" # At least one package is installed
            pkginstlist="$package $pkginstlist"
        fi
    done
    if [ $pkginst = "y" ]; then
        echo "It appears that the folowing package(s) are already installed:"
        echo "$pkginstlist"
        echo "This installer is designed to install and configure Sentora on a clean OS installation only!"
        echo -e "\nPlease re-install your OS before attempting to install using this script."
        exit 1
    fi
    unset pkginst
    unset pkginstlist
fi

# *************************************************
#--- Prepare or query informations required to install

# Update repositories and Install wget and util used to grab server IP
echo -e "\n-- Installing wget and dns utils required to manage inputs"
if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
    apt-get -yqq update   #ensure we can install
    $PACKAGE_INSTALLER dnsutils
fi
$PACKAGE_INSTALLER wget 

extern_ip="$(wget -qO- http://api.sentora.org/ip.txt)"
#local_ip=$(ifconfig eth0 | sed -En 's|.*inet [^0-9]*(([0-9]*\.){3}[0-9]*).*$|\1|p')
local_ip=$(ip addr show | awk '$1 == "inet" && $3 == "brd" { sub (/\/.*/,""); print $2 }')

# Enable parameters to be entered on commandline, required for vagrant install
#   -d <panel-domain>
#   -i <server-ip> (or -i local or -i public, see below)
#   -t <timezone-string>
# like :
#   sentora_install.sh -t Europe/Paris -d panel.domain.tld -i xxx.xxx.xxx.xxx
# notes:
#   -d and -i must be both present or both absent
#   -i local  force use of local detected ip
#   -i public  force use of public detected ip
#   if -t is used without -d/-i, timezone is set from value given and not asked to user
#   if -t absent and -d/-i are present, timezone is not set at all

while getopts d:i:t: opt; do
  case $opt in
  d)
      PANEL_FQDN=$OPTARG
      INSTALL="auto"
      ;;
  i)
      PUBLIC_IP=$OPTARG
      if [[ "$PUBLIC_IP" == "local" ]] ; then
          PUBLIC_IP=$local_ip
      elif [[ "$PUBLIC_IP" == "public" ]] ; then
          PUBLIC_IP=$extern_ip
      fi
      ;;
  t)
      echo "$OPTARG" > /etc/timezone
      tz=$(cat /etc/timezone)
      ;;
  esac
done
if [[ ("$PANEL_FQDN" != "" && "$PUBLIC_IP" == "") || 
      ("$PANEL_FQDN" == "" && "$PUBLIC_IP" != "") ]] ; then
    echo "-d and -i must be both present or both absent."
    exit 2
fi

if [[ "$tz" == "" && "$PANEL_FQDN" == "" ]] ; then
    # Propose selection list for the time zone
    echo "Preparing to select timezone, please wait a few seconds..."
    $PACKAGE_INSTALLER tzdata
    # setup server timezone
    if [[ "$OS" = "CentOs" ]]; then
        # make tzselect to save TZ in /etc/timezone
        echo "echo \$TZ > /etc/timezone" >> /usr/bin/tzselect
        tzselect
        tz=$(cat /etc/timezone)
    elif [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
        dpkg-reconfigure tzdata
        tz=$(cat /etc/timezone)
    fi
fi
# clear timezone information to focus user on important notice
clear

# Installer parameters
if [[ "$PANEL_FQDN" == "" ]] ; then
    echo -e "\n\e[1;33m=== Informations required to build your server ===\e[0m"
    echo 'The installer requires 2 pieces of information:'
    echo ' 1) the sub-domain that you want to use to access Sentora panel,'
    echo '   - do not use your main domain (like domain.com)'
    echo '   - use a sub-domain, e.g panel.domain.com'
    echo '   - or use the server hostname, e.g server1.domain.com'
    echo '   - DNS must already be configured and pointing to the server IP'
    echo '       for this sub-domain'
    echo ' 2) The public IP of the server.'
    echo ''

    PANEL_FQDN="$(/bin/hostname)"
    PUBLIC_IP=$extern_ip
    while true; do
        echo ""
        read -r -e -p "Enter the sub-domain you want to access Sentora panel: " -i "$PANEL_FQDN" PANEL_FQDN

        if [[ "$PUBLIC_IP" != "$local_ip" ]]; then
          echo -e "\nThe public IP of the server is $PUBLIC_IP. Its local IP is $local_ip"
          echo "  For a production server, the PUBLIC IP must be used."
        fi  
        read -r -e -p "Enter (or confirm) the public IP for this server: " -i "$PUBLIC_IP" PUBLIC_IP
        echo ""

        # Checks if the panel domain is a subdomain
        sub=$(echo "$PANEL_FQDN" | sed -n 's|\(.*\)\..*\..*|\1|p')
        if [[ "$sub" == "" ]]; then
            echo -e "\e[1;31mWARNING: $PANEL_FQDN is not a subdomain!\e[0m"
            confirm="true"
        fi

        # Checks if the panel domain is already assigned in DNS
		
		# Obsolete now using external source for FQDN to IP. 
        #dns_panel_ip=$(host "$PANEL_FQDN"|grep address|cut -d" " -f4) // Obsolete for modern VM's due to hostname setup in /etc/hosts
		dns_panel_ip=$(wget -qO- http://api.sentora.org/hostname.txt?domain="$PANEL_FQDN")
		
        if [[ "$dns_panel_ip" == "" ]]; then
            echo -e "\e[1;31mWARNING: $PANEL_FQDN is not defined in your DNS!\e[0m"
            echo "  You must add records in your DNS manager (and then wait until propagation is done)."
            echo "  For more information, read the Sentora documentation:"
            echo "   - http://docs.sentora.org/index.php?node=7 (Installing Sentora)"
            echo "   - http://docs.sentora.org/index.php?node=51 (Installer questions)"
            echo "  If this is a production installation, set the DNS up as soon as possible."
            confirm="true"
        else
            echo -e "\e[1;32mOK\e[0m: DNS successfully resolves $PANEL_FQDN to $dns_panel_ip"

            # Check if panel domain matches public IP
            if [[ "$dns_panel_ip" != "$PUBLIC_IP" ]]; then
                echo -e -n "\e[1;31mWARNING: $PANEL_FQDN DNS record does not point to $PUBLIC_IP!\e[0m"
                echo "  Sentora will not be reachable from http://$PANEL_FQDN"
            fi
        fi

                confirm="true"
        if [[ "$PUBLIC_IP" != "$extern_ip" && "$PUBLIC_IP" != "$local_ip" ]]; then
            echo -e -n "\e[1;31mWARNING: $PUBLIC_IP does not match detected IP !\e[0m"
            echo "  Sentora will not work with this IP..."
                confirm="true"
        fi
      
        echo ""
        # if any warning, ask confirmation to continue or propose to change
        if [[ "$confirm" != "" ]] ; then
            echo "There are some warnings..."
            echo "Are you really sure that you want to setup Sentora with these parameters?"
            read -r -e -p "(y):Accept and install, (n):Change domain or IP, (q):Quit installer? " yn
            case $yn in
                [Yy]* ) break;;
                [Nn]* ) continue;;
                [Qq]* ) exit;;
            esac
        else
            read -r -e -p "All is ok. Do you want to install Sentora now (y/n)? " yn
            case $yn in
                [Yy]* ) break;;
                [Nn]* ) exit;;
            esac
        fi
    done
fi

# ***************************************
# Installation really starts here

echo -e "\n# -------------------------------------------------------------------------------"

#--- Setup Sentora Admin contact info

echo -e "\n--- Please Enter vaild contact info for the Sentora system admin or owner below:\n"

# Get Admin contact info 
# ---- Name
while true
do
    read -r -e -p "Enter Full name: " -i "$ADMIN_NAME" ADMIN_NAME
    echo
    if [ -n "$ADMIN_NAME" ]
    then
        break
    else
        echo "Entry is Blank. Try again."
    fi
done

# --- Email
while true
do
    read -r -e -p "Enter admin email: " -i "$ADMIN_EMAIL" ADMIN_EMAIL
    echo
    if [[ "$ADMIN_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}$ ]]
    then
        break
    else
        echo "Email address $ADMIN_EMAIL is invalid."
    fi
done

# ---- Phone Number
while true
do
    read -r -e -p "Enter Phone Number: " -i "$ADMIN_PHONE" ADMIN_PHONE
    echo
    if [ -n "$ADMIN_PHONE" ]
    then
        break
    else
        echo "Entry is Blank. Try again."
    fi
done

# ---- Address
while true
do
    read -r -e -p "Enter Street Address: " -i "$ADMIN_ADDRESS" ADMIN_ADDRESS
    echo
    if [ -n "$ADMIN_ADDRESS" ]
    then
        break
    else
        echo "Entry is Blank. Try again."
    fi
done

# ---- Address - City, State or Province
while true
do
    read -r -e -p "Enter City, State or Province: " -i "$ADMIN_PROVINCE" ADMIN_PROVINCE
    echo
    if [ -n "$ADMIN_PROVINCE" ]
    then
        break
    else
        echo "Entry is Blank. Try again."
    fi
done

# ---- Address - Postal code
while true
do
    read -r -e -p "Enter Postal code: " -i "$ADMIN_POSTALCODE" ADMIN_POSTALCODE
    echo
    if [ -n "$ADMIN_POSTALCODE" ]
    then
        break
    else
        echo "Entry is Blank. Try again."
    fi
done

# ---- Address - Country
while true
do
    read -r -e -p "Enter Country: " -i "$ADMIN_COUNTRY" ADMIN_COUNTRY
    echo
    if [ -n "$ADMIN_COUNTRY" ]
    then
        break
    else
        echo "Entry is Blank. Try again."
    fi
done

echo -e "\n# -------------------------------------------------------------------------------\n"

#--- Set custom logging methods so we create a log file in the current working directory.
logfile=$(date +%Y-%m-%d_%H.%M.%S_sentora_install.log)
touch "$logfile"
exec > >(tee "$logfile")
exec 2>&1

echo "Installer version $SENTORA_INSTALLER_VERSION"
echo "Sentora core version $SENTORA_CORE_VERSION"
echo ""
echo "Installing Sentora $SENTORA_CORE_VERSION at http://$PANEL_FQDN and ip $PUBLIC_IP"
echo "on server under: $OS  $VER  $ARCH"
uname -a

# Function to disable a file by appending its name with _disabled
disable_file() {
    mv "$1" "$1_disabled_by_sentora" &> /dev/null
}

#--- AppArmor must be disabled to avoid problems
if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
    [ -f /etc/init.d/apparmor ]
    if [ $? = "0" ]; then
        echo -e "\n-- Disabling and removing AppArmor, please wait..."
        /etc/init.d/apparmor stop &> /dev/null
        update-rc.d -f apparmor remove &> /dev/null
        apt-get remove -y --purge apparmor* &> /dev/null
        disable_file /etc/init.d/apparmor &> /dev/null
        echo -e "AppArmor has been removed."
    fi
fi

#--- Adapt repositories and packages sources
echo -e "\n-- Updating repositories and packages sources"
if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then 
    # Update the enabled Aptitude repositories
    echo -ne "\nUpdating Aptitude Repos: " >/dev/tty

    mkdir -p "/etc/apt/sources.list.d.save"
    cp -R "/etc/apt/sources.list.d/*" "/etc/apt/sources.list.d.save" &> /dev/null
    rm -rf "/etc/apt/sources.list/*"
    cp "/etc/apt/sources.list" "/etc/apt/sources.list.save"

    if [[ "$VER" = "24.04" ]]; then
        cat > /etc/apt/sources.list <<EOF
#Depots main restricted
deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc) main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc)-security main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc)-updates main restricted universe multiverse
EOF
    elif [ "$VER" = "12"  ]; then
        cat > /etc/apt/sources.list <<EOF
			deb http://httpredir.debian.org/debian $(lsb_release -sc) main
			deb-src http://httpredir.debian.org/debian $(lsb_release -sc) main
			
			deb http://httpredir.debian.org/debian $(lsb_release -sc)-updates main
			deb-src http://httpredir.debian.org/debian $(lsb_release -sc)-updates main
			
			#deb http://security.debian.org/ $(lsb_release -sc)/updates main
			#deb-src http://security.debian.org/ $(lsb_release -sc)/updates main
			
			deb http://deb.debian.org/debian-security $(lsb_release -sc)-security main
			deb-src http://deb.debian.org/debian-security $(lsb_release -sc)-security main
EOF

    else
        cat > /etc/apt/sources.list <<EOF
#Depots main restricted
deb http://archive.ubuntu.com/ubuntu/ $(lsb_release -sc) main restricted
deb http://security.ubuntu.com/ubuntu $(lsb_release -sc)-security main restricted
deb http://archive.ubuntu.com/ubuntu/ $(lsb_release -sc)-updates main restricted
 
deb-src http://archive.ubuntu.com/ubuntu/ $(lsb_release -sc) main restricted
deb-src http://archive.ubuntu.com/ubuntu/ $(lsb_release -sc)-updates main restricted
deb-src http://security.ubuntu.com/ubuntu $(lsb_release -sc)-security main restricted

#Depots Universe Multiverse 
deb http://archive.ubuntu.com/ubuntu/ $(lsb_release -sc) universe multiverse
deb http://security.ubuntu.com/ubuntu $(lsb_release -sc)-security universe multiverse
deb http://archive.ubuntu.com/ubuntu/ $(lsb_release -sc)-updates universe multiverse

deb-src http://archive.ubuntu.com/ubuntu/ $(lsb_release -sc) universe multiverse
deb-src http://security.ubuntu.com/ubuntu $(lsb_release -sc)-security universe multiverse
deb-src http://archive.ubuntu.com/ubuntu/ $(lsb_release -sc)-updates universe multiverse
EOF
    fi
fi

#--- List all already installed packages (may help to debug)
echo -e "\n-- Listing of all packages installed:"
if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
    dpkg --get-selections
fi

#--- Ensures that all packages are up to date
echo -e "\n-- Updating+upgrading system, it may take some time..."
if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
    apt-get -yqq update
    apt-get -yqq upgrade
fi

#--- Install utility packages required by the installer and/or Sentora.
echo -e "\n-- Downloading and installing required tools..."
if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
    $PACKAGE_INSTALLER sudo vim make zip unzip debconf-utils at build-essential bash-completion ca-certificates e2fslibs
fi

#--- Download Sentora archive from GitHub
echo -e "\n-- Downloading Sentora, Please wait, this may take several minutes, the installer will continue after this is complete!"
# Get latest sentora
while true; do

	# Sentora REPO
    wget -nv -O sentora_core.zip https://github.com/sentora/sentora-core/archive/$SENTORA_CORE_VERSION.zip
		
    if [[ -f sentora_core.zip ]]; then
        break;
    else
        echo "Failed to download sentora core from Github"
        echo "If you quit now, you can run again the installer later."
        read -r -e -p "Press r to retry or q to quit the installer? " resp
        case $resp in
            [Rr]* ) continue;;
            [Qq]* ) exit 3;;
        esac
    fi 
done

###
# Sentora Core Install 
###
mkdir -p $PANEL_PATH
mkdir -p $PANEL_DATA
chown -R root:root $PANEL_PATH
unzip -oq sentora_core.zip -d $PANEL_PATH

#
# Remove PHPUnit module test files (coming soon to the code base).
#
rm -rf $PANEL_PATH/panel/modules/*/tests/
rm -rf $PANEL_PATH/composer.json
rm -rf $PANEL_PATH/composer.lock

###
# ZPanel Upgrade - Clear down all old code (stops orphaned files)
###
if [ ! -L "/etc/zpanel" ] && [ -d "/etc/zpanel" ]; then

    echo -e "Upgrading ZPanelCP 10.1.0 to Sentora v.$SENTORA_CORE_VERSION";

    PANEL_UPGRADE=true

    mv /etc/zpanel/configs /root/zpanel_configs_backup

    ## Move main directories to new sentora location ##
    mv /etc/zpanel/* $PANEL_PATH
    mv /var/zpanel/* $PANEL_DATA

    rm -rf /etc/zpanel/
    rm -rf /var/zpanel/

    ## Removing core for upgrade
    rm -rf $PANEL_PATH/panel/bin/
    rm -rf $PANEL_PATH/panel/dryden/
    rm -rf $PANEL_PATH/panel/etc/
    rm -rf $PANEL_PATH/panel/inc/
    rm -rf $PANEL_PATH/panel/index.php
    rm -rf $PANEL_PATH/panel/LICENSE.md
    rm -rf $PANEL_PATH/panel/README.md
    rm -rf $PANEL_PATH/panel/robots.txt
    rm -rf $PANEL_PATH/panel/modules/aliases
    rm -rf $PANEL_PATH/panel/modules/apache_admin
    rm -rf $PANEL_PATH/panel/modules/backup_admin
    rm -rf $PANEL_PATH/panel/modules/backupmgr
    rm -rf $PANEL_PATH/panel/modules/client_notices
    rm -rf $PANEL_PATH/panel/modules/cron
    rm -rf $PANEL_PATH/panel/modules/distlists
    rm -rf $PANEL_PATH/panel/modules/dns_admin
    rm -rf $PANEL_PATH/panel/modules/dns_manager
    rm -rf $PANEL_PATH/panel/modules/domains
    rm -rf $PANEL_PATH/panel/modules/faqs
    rm -rf $PANEL_PATH/panel/modules/forwarders
    rm -rf $PANEL_PATH/panel/modules/ftp_admin
    rm -rf $PANEL_PATH/panel/modules/ftp_management
    rm -rf $PANEL_PATH/panel/modules/mail_admin
    rm -rf $PANEL_PATH/panel/modules/mailboxes
    rm -rf $PANEL_PATH/panel/modules/manage_clients
    rm -rf $PANEL_PATH/panel/modules/manage_groups
    rm -rf $PANEL_PATH/panel/modules/moduleadmin
    rm -rf $PANEL_PATH/panel/modules/my_account
    rm -rf $PANEL_PATH/panel/modules/mysql_databases
    rm -rf $PANEL_PATH/panel/modules/mysql_users
    rm -rf $PANEL_PATH/panel/modules/news
    rm -rf $PANEL_PATH/panel/modules/packages
    rm -rf $PANEL_PATH/panel/modules/parked_domains
    rm -rf $PANEL_PATH/panel/modules/password_assistant
    rm -rf $PANEL_PATH/panel/modules/phpinfo
    rm -rf $PANEL_PATH/panel/modules/phpmyadmin
    rm -rf $PANEL_PATH/panel/modules/phpsysinfo
    rm -rf $PANEL_PATH/panel/modules/services
    rm -rf $PANEL_PATH/panel/modules/shadowing
    rm -rf $PANEL_PATH/panel/modules/sub_domains
    rm -rf $PANEL_PATH/panel/modules/theme_manager
    rm -rf $PANEL_PATH/panel/modules/updates
    rm -rf $PANEL_PATH/panel/modules/usage_viewer
    rm -rf $PANEL_PATH/panel/modules/webalizer_stats
    rm -rf $PANEL_PATH/panel/modules/webmail
    rm -rf $PANEL_PATH/panel/modules/zpanelconfig
    rm -rf $PANEL_PATH/panel/modules/zpx_core_module

    ###
    # Remove links and files created by installer
    ###
    rm -f /usr/bin/zppy
    rm -f /usr/bin/setso
    rm -f /usr/bin/setzadmin
    
    rm -f /etc/postfix/master.cf
    rm -f /etc/postfix/main.cf
    rm -f /var/spool/vacation/vacation.pl
    rm -f /var/sentora/sieve/globalfilter.sieve
    rm -f /etc/dovecot/dovecot.conf
    rm -f /etc/proftpd.conf

    mysqlpassword=$(cat /etc/sentora/panel/cnf/db.php | grep "pass" | cut -d \' -f 2);

    ## Do NOT copy the new cnf directory
    rm -rf "$PANEL_PATH/sentora-core-$SENTORA_CORE_VERSION/cnf"
 
fi

## cp can be aliased to stop overwriting of files in centos use full path to cp
/bin/cp -rf "$PANEL_PATH/sentora-core-$SENTORA_CORE_VERSION/." "$PANEL_PATH/panel/"
rm sentora_core.zip

rm -rf $PANEL_PATH/sentora-core-*
rm "$PANEL_PATH/panel/LICENSE.md" "$PANEL_PATH/panel/README.md" "$PANEL_PATH/panel/.gitignore"
rm -rf "$PANEL_PATH/_delete_me" "$PANEL_PATH/.gitignore"

#--- Set-up Sentora directories and configure permissions
PANEL_CONF="$PANEL_PATH/configs"

mkdir -p $PANEL_CONF
mkdir -p $PANEL_PATH/docs
mkdir -p $PANEL_DATA/backups

chmod -R 777 $PANEL_PATH/
chmod -R 777 $PANEL_DATA/

# Links for compatibility with zpanel access
ln -s $PANEL_PATH /etc/zpanel
ln -s $PANEL_DATA /var/zpanel

#--- Prepare Sentora executables
chmod +x $PANEL_PATH/panel/bin/zppy 
ln -s $PANEL_PATH/panel/bin/zppy /usr/bin/zppy

chmod +x $PANEL_PATH/panel/bin/setso
ln -s $PANEL_PATH/panel/bin/setso /usr/bin/setso

chmod +x $PANEL_PATH/panel/bin/setzadmin
ln -s $PANEL_PATH/panel/bin/setzadmin /usr/bin/setzadmin

#
#--- Install Sentora preconfig
#
while true; do

	# Sentora REPO
    wget -nv -O sentora_preconfig.zip https://github.com/sentora/sentora-installers/archive/$SENTORA_INSTALLER_VERSION.zip
		
    if [[ -f sentora_preconfig.zip ]]; then
        break;
    else
        echo "Failed to download sentora preconfig from Github"
        echo "If you quit now, you can run again the installer later."
        read -r -e -p "Press r to retry or q to quit the installer? " resp
        case $resp in
            [Rr]* ) continue;;
            [Qq]* ) exit 3;;
        esac
    fi
done

unzip -oq sentora_preconfig.zip
/bin/cp -rf sentora-installers-$SENTORA_INSTALLER_VERSION/preconf/* $PANEL_CONF
rm -rf sentora_preconfig*
rm -rf sentora-installer*

#--- Prepare zsudo
cc -o $PANEL_PATH/panel/bin/zsudo $PANEL_CONF/bin/zsudo.c
sudo chown root $PANEL_PATH/panel/bin/zsudo
chmod +s $PANEL_PATH/panel/bin/zsudo

#--- Resolv.conf protect
chattr -f +i /etc/resolv.conf

#--- Prepare hostname
old_hostname=$(cat /etc/hostname)
# In file hostname
echo "$PANEL_FQDN" > /etc/hostname

# In file hosts
sed -i "/127.0.1.1[\t ]*$old_hostname/d" /etc/hosts
sed -i "s|$old_hostname|$PANEL_FQDN|" /etc/hosts

# For current session
hostname "$PANEL_FQDN"

#--- Some functions used many times below
# Random password generator function
passwordgen() {
    l=$1
    [ "$l" == "" ] && l=16
    tr -dc A-Za-z0-9 < /dev/urandom | head -c "${l}" | xargs
}

# Add first parameter in hosts file as local IP domain
add_local_domain() {
    if ! grep -q "127.0.0.1 $1" /etc/hosts; then
        echo "127.0.0.1 $1" >> /etc/hosts;
    fi
}
#-----------------------------------------------------------
# Install all softwares and dependencies required by Sentora.

if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
    # Disable the DPKG prompts before we run the software install to enable fully automated install.
    export DEBIAN_FRONTEND=noninteractive
fi

##
#--- MySQL
##
echo -e "\n-- Installing MySQL"
$PACKAGE_INSTALLER "$DB_PCKG" ######## This isnt right
if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
    $PACKAGE_INSTALLER bsdutils libsasl2-modules-sql libsasl2-modules
    if [[ "$VER" = "24.04" || "$VER" = "12" ]]; then
        $PACKAGE_INSTALLER db4.7-util
    fi
    MY_CNF_PATH="/etc/mysql/my.cnf"
    DB_SERVICE="mysql"
fi

service $DB_SERVICE start

# setup mysql root password only if mysqlpassword is empty
if [ -z "$mysqlpassword" ]; then
    mysqlpassword=$(passwordgen);
	if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
		if [[ "$VER" = "24.04" ]]; then
			# Mysql 8+
			mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$mysqlpassword';";
		elif [[ "$VER" = "12" ]]; then
			# Debian Maria DB 10+
			mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$mysqlpassword';";
		fi
	fi
fi

# small cleaning of mysql access
mysql -u root -p"$mysqlpassword" -e "DELETE FROM mysql.user WHERE User='root' AND Host != 'localhost'";
mysql -u root -p"$mysqlpassword" -e "DELETE FROM mysql.user WHERE User=''";
mysql -u root -p"$mysqlpassword" -e "FLUSH PRIVILEGES";

# remove test table that is no longer used
mysql -u root -p"$mysqlpassword" -e "DROP DATABASE IF EXISTS test";

# secure SELECT "hacker-code" INTO OUTFILE 
sed -i "s|\[mysqld\]|&\nsecure-file-priv = /var/tmp|" $MY_CNF_PATH

# setup sentora access and core database
if [ $PANEL_UPGRADE == true ]; then

    mysql -u root -p"$mysqlpassword" < $PANEL_CONF/sentora-update/zpanel/sql/update-structure.sql
    mysql -u root -p"$mysqlpassword" < $PANEL_CONF/sentora-update/zpanel/sql/update-data.sql
    
    mysqldump -u root -p"$mysqlpassword" zpanel_core | mysql -u root -p"$mysqlpassword" -D sentora_core
    mysqldump -u root -p"$mysqlpassword" zpanel_postfix | mysql -u root -p"$mysqlpassword" -D sentora_postfix
    mysqldump -u root -p"$mysqlpassword" zpanel_proftpd | mysql -u root -p"$mysqlpassword" -D sentora_proftpd
    mysqldump -u root -p"$mysqlpassword" zpanel_roundcube | mysql -u root -p"$mysqlpassword" -D sentora_roundcube

    sed -i "s|zpanel_core|sentora_core|" $PANEL_PATH/panel/cnf/db.php
else
    sed -i "s|YOUR_ROOT_MYSQL_PASSWORD|$mysqlpassword|" $PANEL_PATH/panel/cnf/db.php
    mysql -u root -p"$mysqlpassword" < $PANEL_CONF/sentora-install/sql/sentora_core.sql
fi
# Register mysql/mariadb service for autostart
if [[ "$OS" = "CentOs" ]]; then
    if [[ "$VER" == "7" || "$VER" == "8" ]]; then
        systemctl enable "$DB_SERVICE".service
    else
        #chkconfig "$DB_SERVICE" on
		systemctl enable "$DB_SERVICE"
    fi
fi

# NEED TO FIX UBUNTU 24.04 & Debian 12 SETTING MYSQL-BIND option TO SERVER IP (127.0.0.1) NOT LOCALHOST
if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
	sed -i "s|bind-address = .*|bind-address = 127.0.0.1|" /etc/mysql/mysql.conf.d/mysqld.cnf
fi

##
#--- Postfix
##
echo -e "\n-- Installing Postfix"
if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
    $PACKAGE_INSTALLER postfix postfix-mysql
    USR_LIB_PATH="/usr/lib"
fi

postfixpassword=$(passwordgen);
if [ $PANEL_UPGRADE == false ]; then
    mysql -u root -p"$mysqlpassword" < $PANEL_CONF/sentora-install/sql/sentora_postfix.sql
fi

# OLD
## grant will also create users which don't exist and update existing users with password ##
##mysql -u root -p"$mysqlpassword" -e "GRANT ALL ON sentora_postfix .* TO 'postfix'@'localhost' identified by '$postfixpassword';";

# Add User for Postfix DB
mysql -u root -p"$mysqlpassword" -e "CREATE USER postfix@localhost IDENTIFIED BY '$postfixpassword';";
# Grant ALL PRIVILEGES to Postfix User
mysql -u root -p"$mysqlpassword" -e "GRANT ALL PRIVILEGES ON sentora_postfix .* TO 'postfix'@'localhost';";

mkdir $PANEL_DATA/vmail
useradd -r -g mail -d $PANEL_DATA/vmail -s /sbin/nologin -c "Virtual maildir" vmail
chown -R vmail:mail $PANEL_DATA/vmail
chmod -R 770 $PANEL_DATA/vmail

mkdir -p /var/spool/vacation
useradd -r -d /var/spool/vacation -s /sbin/nologin -c "Virtual vacation" vacation
chown -R vacation:vacation /var/spool/vacation
chmod -R 770 /var/spool/vacation

#Removed optional transport that was leaved empty, until it is fully handled.
#ln -s $PANEL_CONF/postfix/transport /etc/postfix/transport
#postmap /etc/postfix/transport

add_local_domain "$PANEL_FQDN"
add_local_domain "autoreply.$PANEL_FQDN"

rm -rf /etc/postfix/main.cf /etc/postfix/master.cf
ln -s $PANEL_CONF/postfix/master.cf /etc/postfix/master.cf
ln -s $PANEL_CONF/postfix/main.cf /etc/postfix/main.cf
ln -s $PANEL_CONF/postfix/vacation.pl /var/spool/vacation/vacation.pl

sed -i "s|!POSTFIX_PASSWORD!|$postfixpassword|" $PANEL_CONF/postfix/*.cf
sed -i "s|!POSTFIX_PASSWORD!|$postfixpassword|" $PANEL_CONF/postfix/vacation.conf
# tg - Set default vacation 'from' domain
sed -i "s|!POSTFIX_VACATION!|$PANEL_FQDN|" $PANEL_CONF/postfix/vacation.conf
sed -i "s|!PANEL_FQDN!|$PANEL_FQDN|" $PANEL_CONF/postfix/main.cf

sed -i "s|!USR_LIB!|$USR_LIB_PATH|" $PANEL_CONF/postfix/master.cf
sed -i "s|!USR_LIB!|$USR_LIB_PATH|" $PANEL_CONF/postfix/main.cf
sed -i "s|!SERVER_IP!|$PUBLIC_IP|" $PANEL_CONF/postfix/main.cf 

VMAIL_UID=$(id -u vmail)
MAIL_GID=$(sed -nr "s/^mail:x:([0-9]+):.*/\1/p" /etc/group)
sed -i "s|!POS_UID!|$VMAIL_UID|" $PANEL_CONF/postfix/main.cf
sed -i "s|!POS_GID!|$MAIL_GID|" $PANEL_CONF/postfix/main.cf

# remove unusued directives that issue warnings
sed -i '/virtual_mailbox_limit_maps/d' $PANEL_CONF/postfix/main.cf
sed -i '/smtpd_bind_address/d' $PANEL_CONF/postfix/master.cf

# Register postfix service for autostart (it is automatically started)
if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
	if [[ "$VER" = "24.04" || "$VER" = "12" ]]; then
        #chkconfig postfix on
		systemctl enable postfix
    fi
fi

# Edit deamon_directory in postfix main.cf to fix startup issue.
if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
	if [[ "$VER" = "24.04" || "$VER" = "12" ]]; then
		sed -i "s|daemon_directory = /usr/lib/postfix|daemon_directory = /usr/lib/postfix/sbin|" $PANEL_CONF/postfix/main.cf
	fi
fi

##
#--- Dovecot (includes Sieve)
##
echo -e "\n-- Installing Dovecot"
if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
    $PACKAGE_INSTALLER dovecot-mysql dovecot-imapd dovecot-pop3d dovecot-common dovecot-managesieved dovecot-lmtpd 
    sed -i "s|#first_valid_uid = ?|first_valid_uid = $VMAIL_UID\nlast_valid_uid = $VMAIL_UID\n\nfirst_valid_gid = $MAIL_GID\nlast_valid_gid = $MAIL_GID|" $PANEL_CONF/dovecot2/dovecot.conf
fi

mkdir -p $PANEL_DATA/sieve
chown -R vmail:mail $PANEL_DATA/sieve
mkdir -p /var/lib/dovecot/sieve/
touch /var/lib/dovecot/sieve/default.sieve
ln -s $PANEL_CONF/dovecot2/globalfilter.sieve $PANEL_DATA/sieve/globalfilter.sieve

rm -rf /etc/dovecot/dovecot.conf
ln -s $PANEL_CONF/dovecot2/dovecot.conf /etc/dovecot/dovecot.conf
sed -i "s|!POSTMASTER_EMAIL!|postmaster@$PANEL_FQDN|" $PANEL_CONF/dovecot2/dovecot.conf
sed -i "s|!POSTFIX_PASSWORD!|$postfixpassword|" $PANEL_CONF/dovecot2/dovecot-dict-quota.conf
sed -i "s|!POSTFIX_PASSWORD!|$postfixpassword|" $PANEL_CONF/dovecot2/dovecot-mysql.conf
sed -i "s|!DOV_UID!|$VMAIL_UID|" $PANEL_CONF/dovecot2/dovecot-mysql.conf
sed -i "s|!DOV_GID!|$MAIL_GID|" $PANEL_CONF/dovecot2/dovecot-mysql.conf

touch /var/log/dovecot.log /var/log/dovecot-info.log /var/log/dovecot-debug.log
chown vmail:mail /var/log/dovecot*
chmod 660 /var/log/dovecot*

# Register dovecot service for autostart and start it
if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
	if [[ "$VER" = "24.04" || "$VER" = "12" ]]; then
        #chkconfig dovecot on
		systemctl enable dovecot
        /etc/init.d/dovecot start
    fi
fi

##
#--- Apache server
##
echo -e "\n-- Installing and configuring Apache"
$PACKAGE_INSTALLER "$HTTP_PCKG"
if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
    $PACKAGE_INSTALLER libapache2-mod-bw
    HTTP_CONF_PATH="/etc/apache2/apache2.conf"
    HTTP_VARS_PATH="/etc/apache2/envvars"
    HTTP_SERVICE="apache2"
    HTTP_USER="www-data"
    HTTP_GROUP="www-data"
    a2enmod rewrite
fi

if ! grep -q "Include $PANEL_CONF/apache/httpd.conf" "$HTTP_CONF_PATH"; then
    echo "Include $PANEL_CONF/apache/httpd.conf" >> "$HTTP_CONF_PATH";
    ## Remove old include
    if [ $PANEL_UPGRADE == true ]; then
        sed -i "s|Include /etc/zpanel/configs/apache/httpd.conf||" "$HTTP_CONF_PATH";
    fi
fi
add_local_domain "$(hostname)"

if ! grep -q "apache ALL=NOPASSWD: $PANEL_PATH/panel/bin/zsudo" /etc/sudoers; then
    echo "apache ALL=NOPASSWD: $PANEL_PATH/panel/bin/zsudo" >> /etc/sudoers;
fi

# Create root directory for public HTTP docs
mkdir -p $PANEL_DATA/hostdata/zadmin/public_html
chown -R $HTTP_USER:$HTTP_GROUP $PANEL_DATA/hostdata/
chmod -R 770 $PANEL_DATA/hostdata/

mysql -u root -p"$mysqlpassword" -e "UPDATE sentora_core.x_settings SET so_value_tx='$HTTP_SERVICE' WHERE so_name_vc='httpd_exe'"
mysql -u root -p"$mysqlpassword" -e "UPDATE sentora_core.x_settings SET so_value_tx='$HTTP_SERVICE' WHERE so_name_vc='apache_sn'"

#Set keepalive on (default is off)
sed -i "s|KeepAlive Off|KeepAlive On|" "$HTTP_CONF_PATH"

# Permissions fix for Apache and ProFTPD (to enable them to play nicely together!)
if ! grep -q "umask 002" "$HTTP_VARS_PATH"; then
    echo "umask 002" >> "$HTTP_VARS_PATH";
fi

# remove default virtual site to ensure Sentora is the default vhost
if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
    # disable completely sites-enabled/000-default.conf
    if [[ "$VER" = "24.04" || "$VER" = "12" ]]; then
        sed -i "s|IncludeOptional sites-enabled|#&|" "$HTTP_CONF_PATH"
    else
        sed -i "s|Include sites-enabled|#&|" "$HTTP_CONF_PATH"
    fi
fi

# Comment "NameVirtualHost" and Listen directives that are handled in vhosts file
if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
    sed -i "s|\(Include ports.conf\)|#\1\n# Ports are now handled in Sentora vhosts file|" "$HTTP_CONF_PATH"
    disable_file /etc/apache2/ports.conf
fi

# adjustments for apache 2.4
if [[ ("$OS" = "Ubuntu" && "$VER" = "24.04") || 
      ("$OS" = "debian" && "$VER" = "12") ]] ; then 
    # Order deny,allow / Deny from all   ->  Require all denied
    sed -i 's|Order deny,allow|Require all denied|I'  $PANEL_CONF/apache/httpd.conf
    sed -i '/Deny from all/d' $PANEL_CONF/apache/httpd.conf

    # Order allow,deny / Allow from all  ->  Require all granted
    sed -i 's|Order allow,deny|Require all granted|I' $PANEL_CONF/apache/httpd-vhosts.conf
    sed -i '/Allow from all/d' $PANEL_CONF/apache/httpd-vhosts.conf

    sed -i 's|Order allow,deny|Require all granted|I'  $PANEL_PATH/panel/modules/apache_admin/hooks/OnDaemonRun.hook.php
    sed -i '/Allow from all/d' $PANEL_PATH/panel/modules/apache_admin/hooks/OnDaemonRun.hook.php

    # Remove NameVirtualHost that is now without effect and generate warning
    sed -i '/NameVirtualHost/{N;d}' $PANEL_CONF/apache/httpd-vhosts.conf
    sed -i '/# NameVirtualHost is/ {N;N;N;N;N;d}' $PANEL_PATH/panel/modules/apache_admin/hooks/OnDaemonRun.hook.php

    # Options must have ALL (or none) +/- prefix, disable listing directories
    sed -i 's| FollowSymLinks [-]Indexes| +FollowSymLinks -Indexes|' $PANEL_PATH/panel/modules/apache_admin/hooks/OnDaemonRun.hook.php
fi

#--- Apache+Mod_SSL
if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
	if [[ "$VER" = "24.04" || "$VER" = "12" ]]; then
		# Install Mod_ssl & openssl
		#$PACKAGE_INSTALLER mod_ssl
		$PACKAGE_INSTALLER openssl
		
		# Activate mod_ssl
		a2enmod ssl 
	fi
	
fi 

#############################
##
#--- PHP Install Starts Here
##
echo -e "\n-Installing OS Default PHP version..."

# Install OS Default PHP version

if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
	if [[ "$VER" = "24.04" || "$VER" = "12" ]]; then	
	
		$PACKAGE_INSTALLER libapache2-mod-php php-common php-bcmath php-cli php-mysql php-gd php-curl php-pear php-imagick php-imap php-xmlrpc php-xsl php-intl php-mbstring php-dev php-zip	
		
		# Prepare PHP-mcrypt files
		$PACKAGE_INSTALLER -y build-essential
		
		# Download needed files
		$PACKAGE_INSTALLER libmcrypt-dev 
	fi
fi

##
echo -e "\n-- Configuring PHP..."
##

# PHP version check (PHP 8.X )

###
# Check supported OS default PHP 8.X installed before continuing
###

if [[ "$VER" = "24.04" || "$VER" = "12" ]]; then

	##### Check PHP 8.x was installed or quit installer.
	PHPVERFULL=$(php -r 'echo phpversion();')
	PHPVER=${PHPVERFULL:0:3} # return 8.x
	
	echo -e "\nDetected PHP: $PHPVER "

	if  [[ "$PHPVER" == 8.* ]]; then
		echo -e "\nPHP $PHPVER installed. Procced installing ..."
	else
		echo -e "\nPHP 8.x not installed. $PHPVER installed. Exiting installer. Please contact your script admin!!"
		exit 1
	fi
fi
	
# Set PHP.ini path**
PHP_INI_PATH="/etc/php/$PHPVER/apache2/php.ini"

# PHP 8.* Extra packages needed by different OS's

if [[ "$OS" = "Ubuntu" && ( "$VER" = "24.04" ) ||
      "$OS" = "debian" && ( "$VER" = "12" ) ]] ; then

	# PHP-mcrypt install code all OS - Check this!!!!!!
			
	# Update Pecl Channels
	echo -e "\n--- Updating PECL Channels..."
	pecl channel-update pecl.php.net
	pecl update-channels
	
	if [[ "$VER" = "24.04" || "$VER" = "12" ]]; then
		# Make pear cache folder to stop error "Trying to access array offset on value of type bool in PEAR/REST.php on line 187"
		mkdir -p /tmp/pear/cache
	fi
	
	# Install PHP-Mcrypt
	echo -e "\n--- Installing PHP-mcrypt..."
	echo -ne '\n' | sudo pecl install mcrypt 

fi

# Setup PHP mcrypt config files by OS
if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then

	if [[ "$VER" = "24.04" ]]; then
				
		# Create php-mcrypt modules file
		touch /etc/php/$PHPVER/mods-available/mcrypt.ini
		echo 'extension=mcrypt.so' >> /etc/php/$PHPVER/mods-available/mcrypt.ini
					
		# Create links to activate PHP-mcrypt
		ln -s /etc/php/$PHPVER/mods-available/mcrypt.ini /etc/php/$PHPVER/apache2/conf.d/20-mcrypt.ini
		ln -s /etc/php/$PHPVER/mods-available/mcrypt.ini /etc/php/$PHPVER/cli/conf.d/20-mcrypt.ini
			
	elif [[ "$VER" = "12" ]]; then
				
		# Create php-mcrypt modules file
		touch /etc/php/$PHPVER/mods-available/mcrypt.ini
		echo 'extension=mcrypt.so' >> /etc/php/$PHPVER/mods-available/mcrypt.ini
					
		# Create links to activate PHP-mcrypt
		ln -s /etc/php/$PHPVER/mods-available/mcrypt.ini /etc/php/$PHPVER/apache2/conf.d/20-mcrypt.ini
		ln -s /etc/php/$PHPVER/mods-available/mcrypt.ini /etc/php/$PHPVER/cli/conf.d/20-mcrypt.ini
	fi		
fi

# Set PHP Memory limit
echo -e "\n-- Setting PHP memory limit to 256MB..."
sed -i "s|memory_limit = .*|memory_limit = 256M|g" $PHP_INI_PATH

# Setup php upload dir
mkdir -p $PANEL_DATA/temp
chmod 1777 $PANEL_DATA/temp/
chown -R $HTTP_USER:$HTTP_GROUP $PANEL_DATA/temp/

# Setup php session save directory
mkdir "$PANEL_DATA/sessions"
chown $HTTP_USER:$HTTP_GROUP "$PANEL_DATA/sessions"
chmod 733 "$PANEL_DATA/sessions"
chmod +t "$PANEL_DATA/sessions"

if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
    sed -i "s|;session.save_path = .*|session.save_path = \"$PANEL_DATA/sessions\"|g" $PHP_INI_PATH
fi

sed -i "/php_value/d" $PHP_INI_PATH
echo "session.save_path = $PANEL_DATA/sessions;" >> $PHP_INI_PATH

# setup timezone and upload temp dir
sed -i "s|;date.timezone =|date.timezone = $tz|g" $PHP_INI_PATH
sed -i "s|;upload_tmp_dir =|upload_tmp_dir = $PANEL_DATA/temp/|g" $PHP_INI_PATH

# Disable php signature in headers to hide it from hackers
sed -i 's|expose_php = On|expose_php = Off|g' $PHP_INI_PATH

#########################################################################################

# -------------------------------------------------------------------------------
# Start Snuffleupagus install with lastest version Below
# -------------------------------------------------------------------------------
	
echo -e "\n-- Installing and configuring Snuffleupagus..."

# Install Snuffleupagus
# Install git
$PACKAGE_INSTALLER git

#setup PHP_PERDIR in Snuffleupagus.c in src
mkdir -p /etc/snuffleupagus
cd /etc || exit

# Clone Snuffleupagus
git clone https://github.com/jvoisin/snuffleupagus

cd /etc/snuffleupagus/src || exit
	
sed -i 's|PHP_INI_SYSTEM|PHP_INI_PERDIR|g' snuffleupagus.c

# Update PCRE - Fix issue with building Snuffleupagus
if [[ "$OS" = "Ubuntu" || "$OS" = "debian" && ( "$VER" = "24.04" || "$VER" = "12" ) ]]; then
	$PACKAGE_INSTALLER libpcre3 libpcre3-dev
fi

# Build Snuffleupagus
phpize
./configure --enable-snuffleupagus
make clean
make
make install

cd ~ || exit
	
if [[ "$OS" = "Ubuntu" || "$OS" = "debian" && ( "$VER" = "24.04" || "$VER" = "12" ) ]]; then

	# Write/create snuffleupagus.rules file 
	echo "# Snuffleupagus needs a blank file to start." >> /etc/php/"$PHPVER"/snuffleupagus.rules
	echo "# OS needs Snuffleupagus(SP) rules disbled for command line by default. Thats why this file is here." >> /etc/php/"$PHPVER"/snuffleupagus.rules
	echo "" >> /etc/php/"$PHPVER"/snuffleupagus.rules
	echo "####" >> /etc/php/"$PHPVER"/snuffleupagus.rules
	echo "# DO NOT ADD CODE HERE. You have been WARNED!!!!!" >> /etc/php/"$PHPVER"/snuffleupagus.rules
	echo "# Adding code here will crash system and add vulnerabilities between vhosts." >> /etc/php/"$PHPVER"/snuffleupagus.rules
	echo "####" >> /etc/php/"$PHPVER"/snuffleupagus.rules
	
	# Enable Snuffleupagus in PHP.ini
	echo -e "\n Updating Ubuntu & Debian PHP.ini Enabling snuffleupagus..."
	
	# Write default PHP Snuffleupagus.ini 
	# default code start
	echo "extension=snuffleupagus.so" >> /etc/php/"$PHPVER"/mods-available/snuffleupagus.ini
	echo "sp.configuration_file=/etc/php/"$PHPVER"/snuffleupagus.rules" >> /etc/php/"$PHPVER"/mods-available/snuffleupagus.ini
		
	# Save/link - mods-available/snuffleupagus.ini to conf.d/20-snuffleupagus.ini
	ln -s /etc/php/"$PHPVER"/mods-available/snuffleupagus.ini /etc/php/"$PHPVER"/apache2/conf.d/20-snuffleupagus.ini
	
fi
	
# Disable PHP EOL message for snuff in apache evrvars file

# Check if code exists. If not, add it.
ENVVARS_FILE="/etc/apache2/envvars"
ENVVARS_STRING="export SP_SKIP_OLD_PHP_CHECK=1"

if ! grep -q -F "$ENVVARS_STRING" "$ENVVARS_FILE"; then
	echo 'Apache Snuff Disable PHP EOL Not Found. Adding'
	
	echo '' >> /etc/apache2/envvars
	echo '## Hide Snuff PHP EOL warning' >> /etc/apache2/envvars
	echo 'export SP_SKIP_OLD_PHP_CHECK=1' >> /etc/apache2/envvars
	
fi

# Register apache(+php) services for autostart and start it
if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
        #chkconfig "$HTTP_SERVICE" on
		systemctl enable "$HTTP_SERVICE"
        "/etc/init.d/$HTTP_SERVICE" start
fi

##
#--- ProFTPd
##
echo -e "\n-- Installing ProFTPD"
if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
    $PACKAGE_INSTALLER proftpd-mod-mysql
    FTP_CONF_PATH='/etc/proftpd/proftpd.conf'
fi

# Create and init proftpd database
if [ $PANEL_UPGRADE == false ]; then
    mysql -u root -p"$mysqlpassword" < $PANEL_CONF/sentora-install/sql/sentora_proftpd.sql
fi

# Create and configure mysql password for proftpd
proftpdpassword=$(passwordgen);
sed -i "s|!SQL_PASSWORD!|$proftpdpassword|" $PANEL_CONF/proftpd/proftpd-mysql.conf

# OLD
#mysql -u root -p"$mysqlpassword" -e "GRANT ALL ON sentora_proftpd .* TO 'proftpd'@'localhost' identified by '$proftpdpassword';";

# Add User for Proftpd DB
mysql -u root -p"$mysqlpassword" -e "CREATE USER proftpd@localhost IDENTIFIED BY '$proftpdpassword';";
# Grant ALL PRIVILEGES to Proftpd User
mysql -u root -p"$mysqlpassword" -e "GRANT ALL PRIVILEGES ON sentora_proftpd .* TO 'proftpd'@'localhost';";

# Assign httpd user and group to all users that will be created
HTTP_UID=$(id -u "$HTTP_USER")
HTTP_GID=$(sed -nr "s/^$HTTP_GROUP:x:([0-9]+):.*/\1/p" /etc/group)
mysql -u root -p"$mysqlpassword" -e "ALTER TABLE sentora_proftpd.ftpuser ALTER COLUMN uid SET DEFAULT $HTTP_UID"
mysql -u root -p"$mysqlpassword" -e "ALTER TABLE sentora_proftpd.ftpuser ALTER COLUMN gid SET DEFAULT $HTTP_GID"
sed -i "s|!SQL_MIN_ID!|$HTTP_UID|" $PANEL_CONF/proftpd/proftpd-mysql.conf

# Setup proftpd base file to call sentora config
rm -f "$FTP_CONF_PATH"
#touch "$FTP_CONF_PATH"
#echo "include $PANEL_CONF/proftpd/proftpd-mysql.conf" >> "$FTP_CONF_PATH";
ln -s "$PANEL_CONF/proftpd/proftpd-mysql.conf" "$FTP_CONF_PATH"

# setup proftpd log dir
mkdir -p $PANEL_DATA/logs/proftpd
chmod -R 644 $PANEL_DATA/logs/proftpd

# Correct bug from package in Ubutu14.04 which screw service proftpd restart
# see https://bugs.launchpad.net/ubuntu/+source/proftpd-dfsg/+bug/1246245
if [[ "$OS" = "Ubuntu" || "$OS" = "debian" && ( "$VER" = "24.04" || "$VER" = "12" ) ]]; then
   sed -i "s|\([ \t]*start-stop-daemon --stop --signal $SIGNAL \)\(--quiet --pidfile \"$PIDFILE\"\)$|\1--retry 1 \2|" /etc/init.d/proftpd
fi

##
#--- BIND
##
echo -e "\n-- Installing and configuring Bind"
if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
    $PACKAGE_INSTALLER bind9 bind9utils
    BIND_PATH="/etc/bind/"
    BIND_FILES="/etc/bind"
    BIND_SERVICE="bind9"
    BIND_USER="bind"
    mysql -u root -p"$mysqlpassword" -e "UPDATE sentora_core.x_settings SET so_value_tx='/var/sentora/logs/bind/bind.log' WHERE so_name_vc='bind_log'"
fi

mysql -u root -p"$mysqlpassword" -e "UPDATE sentora_core.x_settings SET so_value_tx='$BIND_PATH' WHERE so_name_vc='bind_dir'"
mysql -u root -p"$mysqlpassword" -e "UPDATE sentora_core.x_settings SET so_value_tx='$BIND_SERVICE' WHERE so_name_vc='bind_service'"
chmod -R 777 $PANEL_CONF/bind/zones/

# Setup logging directory
mkdir $PANEL_DATA/logs/bind
touch $PANEL_DATA/logs/bind/bind.log $PANEL_DATA/logs/bind/debug.log
chown $BIND_USER $PANEL_DATA/logs/bind/bind.log $PANEL_DATA/logs/bind/debug.log
chmod 660 $PANEL_DATA/logs/bind/bind.log $PANEL_DATA/logs/bind/debug.log

if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
    mkdir -p /var/named/dynamic
    touch /var/named/dynamic/managed-keys.bind
    chown -R bind:bind /var/named/
    chmod -R 777 $PANEL_CONF/bind/etc

    chown root:root $BIND_FILES/rndc.key
    chmod 755 $BIND_FILES/rndc.key
fi

# Some link to enable call from path
ln -s /usr/sbin/named-checkconf /usr/bin/named-checkconf
ln -s /usr/sbin/named-checkzone /usr/bin/named-checkzone
ln -s /usr/sbin/named-compilezone /usr/bin/named-compilezone

# Setup acl IP to forbid zone transfer
sed -i "s|!SERVER_IP!|$PUBLIC_IP|" $PANEL_CONF/bind/named.conf

# Build key and conf files
rm -rf $BIND_FILES/named.conf $BIND_FILES/rndc.conf $BIND_FILES/rndc.key

if [[ "$OS" = "Ubuntu" && ( "$VER" = "24.04" ) ||
	"$OS" = "debian" && ( "$VER" = "12" ) ]] ; then
	# Create rndc-key
	rndc-confgen -a -A hmac-sha256
fi

cat $BIND_FILES/rndc.key $PANEL_CONF/bind/named.conf > $BIND_FILES/named.conf
cat $BIND_FILES/rndc.key $PANEL_CONF/bind/rndc.conf > $BIND_FILES/rndc.conf
rm -f $BIND_FILES/rndc.key

############### - Double check code for Apparmor!!!!
# Ubuntu 22/24.04-Debien Bind9 Fixes ------ HAVE to douable check!!!!!!
if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
	if [[ "$VER" = "24.04" || "$VER" = "12" ]]; then
		echo -e "\n-- Configuring BIND9 fixes"
		# Disable Bind9(Named) from Apparmor. Apparmor reinstalls with apps(MySQL & Bind9) for some reason.
		#ln -s /etc/apparmor.d/usr.sbin.named /etc/apparmor.d/disable/
		#apparmor_parser -R /etc/apparmor.d/usr.sbin.named
	fi
fi
################ - Double check code for Apparmor!!!!

# Disable Named/bind dnssec-lookaside & dnssec-enable
if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
	# Bind/Named v.9.10+ or newer.
	if [[ "$VER" = "24.04" || "$VER" = "12" ]]; then
		sed -i "s|dnssec-lookaside no|#dnssec-lookaside no|g" $BIND_FILES/named.conf
		sed -i "s|dnssec-enable yes|#dnssec-enable no|g" $BIND_FILES/named.conf
	fi
fi

##
#--- CRON and ATD
##
echo -e "\n-- Installing and configuring cron tasks"
if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
    $PACKAGE_INSTALLER cron
    CRON_DIR="/var/spool/cron/crontabs"
    CRON_SERVICE="cron"
fi

CRON_USER="$HTTP_USER"

# prepare daemon crontab
# sed -i "s|!USER!|$CRON_USER|" "$PANEL_CONF/cron/zdaemon" #it screw update search!#
sed -i "s|!USER!|root|" "$PANEL_CONF/cron/zdaemon"
cp "$PANEL_CONF/cron/zdaemon" /etc/cron.d/zdaemon
chmod 644 /etc/cron.d/zdaemon

# prepare user crontabs
CRON_FILE="$CRON_DIR/$CRON_USER"
mysql -u root -p"$mysqlpassword" -e "UPDATE sentora_core.x_settings SET so_value_tx='$CRON_FILE' WHERE so_name_vc='cron_file'"
mysql -u root -p"$mysqlpassword" -e "UPDATE sentora_core.x_settings SET so_value_tx='$CRON_FILE' WHERE so_name_vc='cron_reload_path'"
mysql -u root -p"$mysqlpassword" -e "UPDATE sentora_core.x_settings SET so_value_tx='$CRON_USER' WHERE so_name_vc='cron_reload_user'"
{
    echo "SHELL=/bin/bash"
    echo "PATH=/sbin:/bin:/usr/sbin:/usr/bin"
    echo ""
} > mycron
crontab -u $HTTP_USER mycron
rm -f mycron

chmod 744 "$CRON_DIR"
chown -R $HTTP_USER:$HTTP_USER "$CRON_DIR"
chmod 644 "$CRON_FILE"

# Register cron and atd services for autostart and start them
if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
	if [[ "$VER" = "24.04" || "$VER" = "12" ]]; then
        #chkconfig crond on
		systemctl enable crond
        /etc/init.d/crond start
        /etc/init.d/atd start
    fi
fi

##
#--- phpMyAdmin
##
echo -e "\n-- Configuring phpMyAdmin"
phpmyadminsecret=$(passwordgen 32);
chmod 644 $PANEL_CONF/phpmyadmin/config.inc.php
sed -i "s|\$cfg\['blowfish_secret'\] \= 'SENTORA';|\$cfg\['blowfish_secret'\] \= '$phpmyadminsecret';|" $PANEL_CONF/phpmyadmin/config.inc.php
ln -s $PANEL_CONF/phpmyadmin/config.inc.php $PANEL_PATH/panel/etc/apps/phpmyadmin/config.inc.php
# Remove phpMyAdmin's setup folder in case it was left behind
rm -rf $PANEL_PATH/panel/etc/apps/phpmyadmin/setup

##
#--- PHPsysinfo
##
echo -e "\n-- Configuring PHPsysinfo"
# Setup config file
mv -f /etc/sentora/panel/etc/apps/phpsysinfo/phpsysinfo.ini.new /etc/sentora/panel/etc/apps/phpsysinfo/phpsysinfo.ini

##
#--- Roundcube
##
echo -e "\n-- Configuring Roundcube"

# Import roundcube default MYSQL table
if [ $PANEL_UPGRADE == false ]; then
    mysql -u root -p"$mysqlpassword" < $PANEL_CONF/sentora-install/sql/sentora_roundcube.sql
fi

# Create and configure mysql password for roundcube
roundcubepassword=$(passwordgen);
sed -i "s|!ROUNDCUBE_PASSWORD!|$roundcubepassword|" $PANEL_CONF/roundcube/roundcube_config.inc.php


# OLD 
#mysql -u root -p"$mysqlpassword" -e "GRANT ALL PRIVILEGES ON sentora_roundcube .* TO 'roundcube'@'localhost' identified by '$roundcubepassword';";

# Add User for Roundcube DB
mysql -u root -p"$mysqlpassword" -e "CREATE USER roundcube@localhost IDENTIFIED BY '$roundcubepassword';";
# Grant ALL PRIVILEGES to Roundcube User
mysql -u root -p"$mysqlpassword" -e "GRANT ALL PRIVILEGES ON sentora_roundcube .* TO 'roundcube'@'localhost';";

# Delete Roundcube setup files
rm -r $PANEL_PATH/panel/etc/apps/webmail/SQL
rm -r $PANEL_PATH/panel/etc/apps/webmail/installer

# Create and configure des key
roundcube_des_key=$(passwordgen 24);
sed -i "s|!ROUNDCUBE_DESKEY!|$roundcube_des_key|" $PANEL_CONF/roundcube/roundcube_config.inc.php

# Create and configure specials directories and rights
chown "$HTTP_USER:$HTTP_GROUP" "$PANEL_PATH/panel/etc/apps/webmail/temp"
mkdir "$PANEL_DATA/logs/roundcube"
chown "$HTTP_USER:$HTTP_GROUP" "$PANEL_DATA/logs/roundcube"

# Map config file in roundcube with symbolic links
ln -s $PANEL_CONF/roundcube/roundcube_config.inc.php $PANEL_PATH/panel/etc/apps/webmail/config/config.inc.php
ln -s $PANEL_CONF/roundcube/sieve_config.inc.php $PANEL_PATH/panel/etc/apps/webmail/plugins/managesieve/config.inc.php

##
#--- Webalizer
##
echo -e "\n-- Configuring Webalizer"

if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
	$PACKAGE_INSTALLER webalizer
	rm -rf /etc/webalizer/webalizer.conf
fi

#--- Set some Sentora database entries using. setso and setzadmin (require PHP)
echo -e "\n-- Configuring Sentora"
zadminpassword=$(passwordgen);
setzadmin --set "$zadminpassword";
$PANEL_PATH/panel/bin/setso --set sentora_domain "$PANEL_FQDN"
$PANEL_PATH/panel/bin/setso --set server_ip "$PUBLIC_IP"

# if not release, set beta version in database
if [[ $(echo "$SENTORA_CORE_VERSION" | sed  's|.*-\(beta\).*$|\1|') = "beta"  ]] ; then
    $PANEL_PATH/panel/bin/setso --set dbversion "$SENTORA_CORE_VERSION"
fi

# Make the daemon to run/build vhosts file.
$PANEL_PATH/panel/bin/setso --set apache_changed "true"
php -q $PANEL_PATH/panel/bin/daemon.php

##
#--- Firewall ? SHOULD WE???
##

##
#--- Fail2ban - This should be standard with install. We need a module to help user with settings. Maybe soon!
##

##
#--- Logrotate
##

#  Download and install logrotate
echo -e "\n-- Installing Logrotate"
$PACKAGE_INSTALLER logrotate

#	Link the configfiles 
ln -s $PANEL_CONF/logrotate/Sentora-apache /etc/logrotate.d/Sentora-apache
ln -s $PANEL_CONF/logrotate/Sentora-proftpd /etc/logrotate.d/Sentora-proftpd
ln -s $PANEL_CONF/logrotate/Sentora-dovecot /etc/logrotate.d/Sentora-dovecot

#	Configure the postrotatesyntax for different OS
if [[ "$OS" = "Ubuntu" || "$OS" = "debian" ]]; then
	sed -i 's|systemctl reload httpd > /dev/null|/etc/init.d/apache2 reload > /dev/null|' $PANEL_CONF/logrotate/Sentora-apache
	sed -i 's|systemctl reload proftpd > /dev/null|/etc/init.d/proftpd force-reload > /dev/null|' $PANEL_CONF/logrotate/Sentora-proftpd
fi

#--- Resolv.conf deprotect
chattr -i /etc/resolv.conf

## Leaving this just incase. ***
#--- Restart all services to capture output messages, if any
if [[ "$OS" = "CentOs" ]]; then
    # CentOs does not return anything except redirection to systemctl :-(
    service() {
       echo "Restarting $1"
       systemctl restart "$1.service"
    }
fi

# Clean up files needed for install/update
# N/A

echo -e "# -------------------------------------------------------------------------------"

# Set admin contact info to zadmin profile

echo -e "\n--- Updating Admin contact Info..."
mysql -u root -p"$mysqlpassword" -e "UPDATE sentora_core.x_accounts SET ac_email_vc='$ADMIN_EMAIL' WHERE sentora_core.x_accounts.ac_id_pk = 1"
mysql -u root -p"$mysqlpassword" -e "UPDATE sentora_core.x_profiles SET ud_fullname_vc='$ADMIN_NAME', ud_phone_vc='$ADMIN_PHONE', ud_address_tx='$ADMIN_ADDRESS\r\n$ADMIN_PROVINCE $ADMIN_POSTALCODE\r\n$ADMIN_COUNTRY', ud_postcode_vc='$ADMIN_POSTALCODE' WHERE sentora_core.x_profiles.ud_id_pk = 1"

echo -e "\n--- Done Updating admin contact info.\n"

echo -e "# -------------------------------------------------------------------------------"

echo -e "\n--- Restarting Services"
echo -e "Restarting $DB_SERVICE..."
service "$DB_SERVICE" restart
echo -e "Restarting $HTTP_SERVICE..."
service "$HTTP_SERVICE" restart
echo -e "Restarting Postfix..."
service postfix restart
echo -e "Restarting Dovecot..."
service dovecot restart
echo -e "Restarting CRON..."
service "$CRON_SERVICE" restart
echo -e "Restarting Bind9/Named..."
service "$BIND_SERVICE" restart
echo -e "Restarting Proftpd..."
service proftpd restart
echo -e "Restarting ATD..."
service atd restart

echo -e "\n--- Finished Restarting Services...\n"

#--- Store the passwords for user reference
{
    echo "Server IP address : $PUBLIC_IP"
    echo "Panel URL         : http://$PANEL_FQDN"
    echo "zadmin Password   : $zadminpassword"
    echo ""
    echo "MySQL Root Password      : $mysqlpassword"
    echo "MySQL Postfix Password   : $postfixpassword"
    echo "MySQL ProFTPd Password   : $proftpdpassword"
    echo "MySQL Roundcube Password : $roundcubepassword"
} >> /root/passwords.txt
chmod 600 /root/passwords.txt

#--- Advise the admin that Sentora is now installed and accessible.
{
echo "########################################################"
echo " Congratulations Sentora has now been installed on your"
echo " server. Please review the log file left in /root/ for "
echo " any errors encountered during installation."
echo ""
echo " Login to Sentora at http://$PANEL_FQDN"
echo " Sentora Username  : zadmin"
echo " Sentora Password  : $zadminpassword"
echo ""
echo " MySQL Root Password      : $mysqlpassword"
echo " MySQL Postfix Password   : $postfixpassword"
echo " MySQL ProFTPd Password   : $proftpdpassword"
echo " MySQL Roundcube Password : $roundcubepassword"
echo "   (theses passwords are saved in /root/passwords.txt)"
echo "########################################################"
echo ""
} &>/dev/tty

# Wait until the user have read before restarts the server...
if [[ "$INSTALL" != "auto" ]] ; then
    while true; do
        read -r -e -p "Restart your server now to complete the install (y/n)? " rsn
        case $rsn in
            [Yy]* ) break;;
            [Nn]* ) exit;
        esac
    done
    shutdown -r now
fi
