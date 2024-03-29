#!/bin/bash
# SentinelOne's SACK CVE Fixer.
# Copyright (C) 2019  SentinelOne

PERSISTENCE_PATH=/etc/cron.d/sack_check_fix

function usage(){
    echo "Usage: $0 [check|install]"
    exit 1
}

if [[ $# -ne 1 ]]; then
    usage
fi

if [[ "$1" =  "check" ]]; then
    check=1
elif [[ "$1" = "install" ]]; then
    check=0
else
    usage
fi

# Is root?
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root." 
   exit 1
fi


# Get info
echo -n "[+] Getting Linux version... "
uname -o | grep -i linux 2>&1 > /dev/null || ( echo;echo "[-] Not Linux. Exiting." ; exit 1 )
kernel_version=$(uname -r | cut -d- -f1)
echo $kernel_version


# Save original value
export mtu_probing=$(sysctl -n net.ipv4.tcp_mtu_probing)
echo "[+] Current mtu_probing = $mtu_probing"


echo -n "[+] Checking IP TCP MSS limit... "
iptables -C INPUT -p tcp -m tcpmss --mss 1:500 -j DROP > /dev/null 2>&1
export ip_rule=$?
if [[ $ip_rule -eq 0 ]]; then
    echo "exists."
else
    echo "doesn't exist."
fi

echo -n "[+] Checking IPv6 TCP MSS limit... "
ip6tables -C INPUT -p tcp -m tcpmss --mss 1:500 -j DROP > /dev/null 2>&1
export ip6_rule=$?
if [[ $ip6_rule -eq 0 ]]; then
    echo "exists."
else
    echo "doesn't exist."
fi

function version_lt(){
    test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" != "$1" &&
    ([[ "$ip_rule" != "0" ]] || [[ "$ip6_rule" != "0" ]] || [[ "$mtu_probing" != "0" ]])
}
function version_ge(){
    test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" == "$1" &&
    ([[ "$ip_rule" != "0" ]] || [[ "$ip6_rule" != "0" ]] || [[ "$mtu_probing" != "0" ]])
}

echo "[+] Checking Linux version against vulnerabilities..."
echo -n "[+] CVE-2019-11477 - "
version_ge $kernel_version 2.6.29 && echo "vulnerable." || echo "not vulnerable."
echo -n "[+] CVE-2019-11478 - " # relevant to all Linux versions
version_lt $kernel_version 5.2.0 && echo "vulnerable." || echo "not vulnerable."
echo -n "[+] CVE-2019-11479 - " # relevant to all Linux versions
version_lt $kernel_version 5.2.0 && echo "vulnerable." || echo "not vulnerable."

if [[ $check -eq 1 ]]; then
    exit 0
fi


# Generate restore script
echo -n "[+] Generating a restore script... "
cat <<EOF>restore.sh
#!/bin/bash

if [[ \$EUID -ne 0 ]]; then
   echo "This script must be run as root." 
   exit 1
fi

original_mtu_probing=$mtu_probing

echo -n "[+] Restoring mtu_probing = \$original_mtu_probing... "
sysctl net.ipv4.tcp_mtu_probing=\$original_mtu_probing > /dev/null
if [[ \$? -eq 0 ]]; then
    echo "done."
else
    echo "failed."
    failed=1
fi

if [[ $ip_rule -ne 0 ]]; then
    echo -n "[+] Restoring iptables rules... "
    iptables -D INPUT -p tcp -m tcpmss --mss 1:500 -j DROP
    if [[ \$? -eq 0 ]]; then
        echo "done."
    else
        echo "failed."
        failed=1
    fi
fi

if [[ $ip6_rule -ne 0 ]]; then
    echo -n "[+] Restoring ip6tables rules... "
    ip6tables -D INPUT -p tcp -m tcpmss --mss 1:500 -j DROP
    if [[ \$? -eq 0 ]]; then
        echo "done."
    else
        echo "failed."
        failed=1
    fi
fi

echo -n "[+] Removing persistence... "
rm -f $PERSISTENCE_PATH
if [[ \$? -eq 0 ]]; then
    echo "done."
else
    echo "failed."
    echo "It's possible there was no persistence on $PERSISTENCE_PATH."
fi

[[ \$failed -eq 0 ]] && echo "Done successfully." || echo "Script ended with errors."
EOF
if [[ $? -eq 0 ]]; then
    echo "done."
else
    echo "failed. can't continue."
    exit 1
fi
chmod +x ./restore.sh


# Setup workarounds
failed=0

echo -n "[+] Setting mtu_probing... "
sysctl net.ipv4.tcp_mtu_probing=0 > /dev/null
if [[ $? -eq 0 ]]; then
    echo "done."
else
    echo "failed."
    failed=1
fi


if [[ $ip_rule -ne 0 ]]; then
    echo -n "[+] Setting iptables rules... "
    iptables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP
    if [[ $? -eq 0 ]]; then
        echo "done."
    else
        echo "failed."
        failed=1
    fi
fi

if [[ $ip6_rule -ne 0 ]]; then
    echo -n "[+] Setting ip6tables rules... "
    ip6tables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP
    if [[ $? -eq 0 ]]; then
        echo "done."
    else
        echo "failed."
        failed=1
    fi
fi


# Install persistence
echo -n "[+] Installing persistence... "
cat <<EOF>$PERSISTENCE_PATH
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

@reboot   root  sysctl net.ipv4.tcp_mtu_probing=0 > /dev/null; iptables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP; ip6tables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP
EOF
if [[ $? -eq 0 ]]; then
    echo "done."
else
    echo "failed."
    echo "After reboot your machine will be vulnerable again. Please ensure your system executes the following on boot:"
    echo "sysctl net.ipv4.tcp_mtu_probing=0 > /dev/null; iptables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP; ip6tables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP"
fi

echo
[[ $failed -eq 0 ]] && echo -e "Done successfully.\nTo restore original settings, please run ./restore.sh" || echo "Script ended with errors."