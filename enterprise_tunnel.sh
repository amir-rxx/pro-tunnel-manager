#!/bin/bash

BASE_DIR="$HOME/.enterprise_tunnel"
PROFILE_DIR="$BASE_DIR/profiles"
LOG_FILE="$BASE_DIR/tunnel.log"

mkdir -p "$PROFILE_DIR"
touch "$LOG_FILE"

log_event() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

check_dependencies() {
    local missing=()
    for pkg in whiptail autossh sshpass; do
        if ! command -v $pkg &> /dev/null; then
            missing+=($pkg)
        fi
    done
    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "Dar hale nasbe pishniazhaye zaroori (${missing[@]})..."
        sudo apt update -y > /dev/null 2>&1
        sudo apt install -y "${missing[@]}" > /dev/null 2>&1
        log_event "Installed missing dependencies: ${missing[*]}"
    fi
}

show_msg() {
    whiptail --title "Payam System" --msgbox "$1" 10 60
}

execute_tunnel() {
    local prof_file=$1
    local mode=$2
    
    source "$prof_file"
    
    local auth_prefix=""
    if [[ -n "$SSH_PASS" ]]; then
        auth_prefix="sshpass -p $SSH_PASS "
    fi
    
    local port_mapping=""
    if [[ "$TUNNEL_TYPE" == "normal" ]]; then
        port_mapping="-L ${LPORT}:${DEST_IP}:${DEST_PORT}"
    else
        port_mapping="-R ${RPORT}:${DEST_IP}:${DEST_PORT}"
    fi

    local autossh_opts="-M 0 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=no -N"
    
    if [[ "$mode" == "background" ]]; then
        export AUTOSSH_GATETIME=0
        eval "${auth_prefix}autossh $autossh_opts -f $port_mapping ${SSH_USER}@${SSH_SERVER}"
        
        if [ $? -eq 0 ]; then
            log_event "Tunnel started in background: Profile $PROFILE_NAME"
            show_msg "Tunnel ba movafaghiyat dar background (ba AutoSSH) ejra shod!"
        else
            log_event "Failed to start tunnel: Profile $PROFILE_NAME"
            show_msg "Khata dar ejraye tunnel. Lotfan moshakhasat ra baresi konid."
        fi
    
    elif [[ "$mode" == "systemd" ]]; then
        local service_name="ssh-tunnel-${PROFILE_NAME}.service"
        local service_path="/etc/systemd/system/$service_name"
        
        local autossh_bin=$(which autossh)
        local sshpass_bin=$(which sshpass)
        local exec_start=""
        
        if [[ -n "$SSH_PASS" ]]; then
            exec_start="$sshpass_bin -p $SSH_PASS $autossh_bin $autossh_opts $port_mapping ${SSH_USER}@${SSH_SERVER}"
        else
            exec_start="$autossh_bin $autossh_opts $port_mapping ${SSH_USER}@${SSH_SERVER}"
        fi

        sudo bash -c "cat > $service_path" <<EOF
[Unit]
Description=AutoSSH Tunnel - $PROFILE_NAME
After=network.target

[Service]
Environment="AUTOSSH_GATETIME=0"
ExecStart=$exec_start
Restart=always
RestartSec=5
User=$USER

[Install]
WantedBy=multi-user.target
EOF

        sudo systemctl daemon-reload
        sudo systemctl enable $service_name
        sudo systemctl start $service_name
        
        log_event "Created Systemd service: $service_name"
        show_msg "Service Systemd ba name $service_name sakhte va faal shod! Tunnel aknoon ba har bar reboot server be soorate khodkar ejra mishavad."
    fi
}

create_new_profile() {
    PROFILE_NAME=$(whiptail --title "Name Profile" --inputbox "Yek name yekta baraye in profile vared konid (bedoone faseleh, masalan: db_tunnel):" 10 60 3>&1 1>&2 2>&3)
    [[ -z "$PROFILE_NAME" ]] && return

    SSH_SERVER=$(whiptail --title "Server Maghsad" --inputbox "IP ya addresse servere SSH (vaset) ra vared konid:" 10 60 3>&1 1>&2 2>&3)
    [[ -z "$SSH_SERVER" ]] && return

    SSH_USER=$(whiptail --title "Name Karbari" --inputbox "Name karbari servere SSH:" 10 60 "root" 3>&1 1>&2 2>&3)
    
    SSH_PASS=$(whiptail --title "Ramze Oboor" --passwordbox "Ramze oboore SSH ra vared konid\n(Agar az kelide SSH estefadeh mikonid khali bogzarid):" 10 60 3>&1 1>&2 2>&3)

    TUNNEL_TYPE=$(whiptail --title "Noe Tunnel" --menu "Noe tunnel ra entekhab konid:" 12 60 2 \
        "normal" "Tunnel Aadi (Local Forwarding)" \
        "reverse" "Tunnel Reverse (Remote Forwarding)" 3>&1 1>&2 2>&3)
    [[ -z "$TUNNEL_TYPE" ]] && return

    if [[ "$TUNNEL_TYPE" == "normal" ]]; then
        LPORT=$(whiptail --title "Porte Mahali" --inputbox "Che porti rooye servere shoma baz shavad? (Local Port):" 10 60 3>&1 1>&2 2>&3)
        DEST_IP=$(whiptail --title "IP Maghsad" --inputbox "IP hadaf dar shabake maghsad (Mamoolan 127.0.0.1):" 10 60 "127.0.0.1" 3>&1 1>&2 2>&3)
        DEST_PORT=$(whiptail --title "Porte Maghsad" --inputbox "Porte service dar maghsad:" 10 60 3>&1 1>&2 2>&3)
        RPORT=""
    else
        RPORT=$(whiptail --title "Porte Remote" --inputbox "Che porti rooye servere SSH baz shavad? (Remote Port):" 10 60 3>&1 1>&2 2>&3)
        DEST_IP=$(whiptail --title "IP Hadaf" --inputbox "IP systemi ke mikhahid rooye server share konid (Mamoolan 127.0.0.1):" 10 60 "127.0.0.1" 3>&1 1>&2 2>&3)
        DEST_PORT=$(whiptail --title "Porte Hadaf" --inputbox "Porte systeme shoma:" 10 60 3>&1 1>&2 2>&3)
        LPORT=""
    fi

    local conf_file="$PROFILE_DIR/$PROFILE_NAME.conf"
    cat > "$conf_file" <<EOF
PROFILE_NAME="$PROFILE_NAME"
SSH_SERVER="$SSH_SERVER"
SSH_USER="$SSH_USER"
SSH_PASS="$SSH_PASS"
TUNNEL_TYPE="$TUNNEL_TYPE"
LPORT="$LPORT"
RPORT="$RPORT"
DEST_IP="$DEST_IP"
DEST_PORT="$DEST_PORT"
EOF

    log_event "Created new profile: $PROFILE_NAME"
    show_msg "Profile $PROFILE_NAME ba movafaghiyat sakhte va zakhire shod."
}

load_profile_menu() {
    local profiles=()
    for file in "$PROFILE_DIR"/*.conf; do
        [[ -e "$file" ]] || break
        local base=$(basename "$file" .conf)
        profiles+=("$base" "Saved Profile")
    done

    if [ ${#profiles[@]} -eq 0 ]; then
        show_msg "Hich profilei yaft nashod! Ebteda yek profile besazid."
        return
    fi

    SELECTED_PROF=$(whiptail --title "Entekhab Profile" --menu "Yeki az profilehaye zakhire shodeh ra entekhab konid:" 15 60 6 "${profiles[@]}" 3>&1 1>&2 2>&3)
    [[ -z "$SELECTED_PROF" ]] && return
    
    ACTION=$(whiptail --title "Amaliyat" --menu "Baraye in profile che kari anjam shavad?" 15 60 4 \
        "1" "Ejra dar background hamin hala" \
        "2" "Tabdil be service daemi (Systemd)" \
        "3" "Hazfe profile" 3>&1 1>&2 2>&3)

    local conf_file="$PROFILE_DIR/$SELECTED_PROF.conf"

    case $ACTION in
        1) execute_tunnel "$conf_file" "background" ;;
        2) execute_tunnel "$conf_file" "systemd" ;;
        3) rm -f "$conf_file"; log_event "Deleted profile: $SELECTED_PROF"; show_msg "Profile hazf shod." ;;
    esac
}

list_tunnels() {
    local tunnels=$(ps aux | grep -E "autossh.*-[LR]" | grep -v grep)
    if [[ -z "$tunnels" ]]; then
        show_msg "Hich tunnel faali dar background yaft nashod."
    else
        local formatted=$(echo "$tunnels" | awk '{print "PID: " $2 "\nCmd: " $13 " " $14 " " $15 " " $16 "\n---"}')
        whiptail --title "Tunnelhaye Faal (Background)" --msgbox "$formatted" 20 70 --scrolltext
    fi
}

kill_tunnel() {
    PID=$(whiptail --title "Tavaghofe Tunnel" --inputbox "Shomare PID tunnel ra baraye bastan vared konid (ya benevisid all baraye tavaghofe hame):" 10 60 3>&1 1>&2 2>&3)
    [[ -z "$PID" ]] && return

    if [[ "$PID" == "all" ]]; then
        pkill -f "autossh.*-[LR]"
        log_event "Killed all autossh background tunnels."
        show_msg "Tamame tunnelhaye background motevaghef shodand."
    elif [[ "$PID" =~ ^[0-9]+$ ]]; then
        kill $PID
        log_event "Killed tunnel PID: $PID"
        show_msg "Prosesse $PID ba movafaghiyat motevaghef shod."
    else
        show_msg "Shomare PID namotabar ast."
    fi
}

check_dependencies

while true; do
    CHOICE=$(whiptail --title "🔥 Enterprise SSH Tunnel Manager 🔥" --menu "Abzare modiriyate pishrafteh tunnel - lotfan yek gozineh ra entekhab konid:" 18 70 6 \
        "1" "Sakhte profile jadid (Tunnel aadi/reverse)" \
        "2" "Modiriyat va ejraye profileha (Background / Systemd)" \
        "3" "Moshahedeye tunnelhaye dar hale ejra" \
        "4" "Motevaghef kardane yek tunnel" \
        "5" "Khorooj" 3>&1 1>&2 2>&3)

    case $CHOICE in
        1) create_new_profile ;;
        2) load_profile_menu ;;
        3) list_tunnels ;;
        4) kill_tunnel ;;
        5) exit 0 ;;
        *) exit 0 ;;
    esac
done
