#!/bin/bash
## Installer by b
## Thanks to Bakerboy, Sosig, Liara, and team for some of the functions / logic.
## b

user=$(whoami)

if [[ ! -d $HOME/.logs ]]; then
    mkdir -p $HOME/.logs
fi

touch "$HOME/.logs/sonarr.log"
log="$HOME/.logs/sonarr.log"

function port() {
    LOW_BOUND=$1
    UPPER_BOUND=$2
    comm -23 <(seq ${LOW_BOUND} ${UPPER_BOUND} | sort) <(ss -Htan | awk '{print $4}' | cut -d':' -f2 | sort -u) | shuf | head -n 1
}

function _install() {
    ssl_port=$(port 14000 16000)
    port=$(port 10000 14000)
    domain=$(hostname -f)

    # Download App
    echo "Downloading Sonarr"
    
    curl -sL "https://services.sonarr.tv/v1/download/develop/latest?version=4&os=linux&runtime=netcore&arch=x64" -o /tmp/sonarr.tar.gz >> "$log" 2>&1 || {
        echo "Download failed."
        exit 1
    }

    # Extract
    echo "Extracting Sonarr"
    tar xfv "/tmp/sonarr.tar.gz" --directory $HOME/ >> "$log" 2>&1 || {
        echo_error "Failed to extract"
        exit 1
    }
    rm -rf /tmp/sonarr.tar.gz

    if [[ ! -d $HOME/.config/systemd/user/ ]]; then
        mkdir -p $HOME/.config/systemd/user/
    fi

    # Service File
    echo "Writing service file"
    cat > "$HOME/.config/systemd/user/sonarr.service" << EOF
[Unit]
Description=Sonarr Daemon
After=syslog.target network.target

[Service]
Type=simple
ExecStart=$HOME/Sonarr/Sonarr -nobrowser -data=$HOME/.config/sonarr/
TimeoutStopSec=20
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    mkdir -p $HOME/.config/sonarr/
    cat > $HOME/.config/sonarr/config.xml << SONARR
<Config>
  <LogLevel>debug</LogLevel>
  <UpdateMechanism>BuiltIn</UpdateMechanism>
  <BindAddress>*</BindAddress>
  <Port>${port}</Port>
  <SslPort>${ssl_port}</SslPort>
  <EnableSsl>False</EnableSsl>
  <LaunchBrowser>False</LaunchBrowser>
  <ApiKey></ApiKey>
  <AuthenticationMethod>None</AuthenticationMethod>
  <UrlBase></UrlBase>
  <Branch>develop</Branch>
</Config>
SONARR

    # Enable/Start Sonarr
    echo "Starting Sonarr"
    systemctl enable --now --user sonarr.service
    echo "Sonarr will be accessible at http://${domain}:${port}"

    echo "Waiting for Sonarr to start"
    sleep 45
    apikey=$(grep -oPm1 "(?<=<ApiKey>)[^<]+" "$HOME/.config/sonarr/config.xml")
    echo "${apikey}"
    if ! timeout 5 bash -c -- "while ! curl -sfkL \"http://127.0.0.1:${port}/api/v1/system/status?apiKey=${apikey}\" >> \"$log\" 2>&1; do sleep 5; done"; then
        echo "Sonarr API not respond as expected. Please make sure Sonarr is running."
        exit 1
    fi
    read -rep "Please set a password for your sonarr user ${user}> " -i "" password
    echo "Applying authentication"
    payload=$(curl -skL "http://127.0.0.1:${port}/api/v1/config/host?apikey=${apikey}" | jq ".authenticationMethod = \"forms\" | .username = \"${user}\" | .password = \"${password}\"")
    curl -sk "http://127.0.0.1:${port}/api/v1/config/host?apikey=${apikey}" -X PUT -H 'Accept: application/json, text/javascript, */*; q=0.01' --compressed -H 'Content-Type: application/json' --data-raw "${payload}" >> "$log"
    sleep 15
    echo "Restarting sonarr"
    systemctl restart --user sonarr
    

    echo "Sonarr v4 has been installed. You can access it at http://${domain}:${port}"
    echo "Remember to check your authentication. This is publicly accessible and will contain your API keys and stuff."
}

function _remove() {
    systemctl disable --now --user sonarr
    rm -rf "$HOME/.config/sonarr/"
    rm -rf "$HOME/Sonarr/"
    echo "Sonarr has been removed."
}

echo 'This is unsupported software. You will not get help with this, please answer `yes` if you understand and wish to proceed'
if [[ -z ${eula} ]]; then
    read -r eula
fi

if ! [[ $eula =~ yes ]]; then
  echo "You did not accept the above. Exiting..."
  exit 1
else
  echo "Proceeding with installation"
fi

echo "Welcome to Sonarr v4 installer..."
echo ""
echo "What do you like to do?"
echo "Logs are stored at ${log}"
echo "install = Install Sonarr v4"
echo "uninstall = Completely removes Sonarr v4"
echo "exit = Exits Installer"
while true; do
    read -r -p "Enter it here: " choice
    case $choice in
        "install")
            _install
            break
            ;;
        "uninstall")
            _remove
            break
            ;;
        "exit")
            break
            ;;
        *)
            echo "Unknown Option."
            ;;
    esac
done
exit