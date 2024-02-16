#!/usr/bin/env bash

# Function to display help information
show_help() {
    echo "Usage: $0 [command] [options]"
    echo "Commands:"
    echo "  ssh-port-forward-postgres <local-port> <remote-host:remote-port>  Forward local TCP IPV4 port to SSH 22 port on the specified remote host, exposing it on the specified remote port"
    echo "  --help                                                            Show this help message"
    echo "  sql                                                               Login to the default database with the schemamap user using psql CLI"
}

# Function to set up SSH port forwarding
ssh_port_forward_postgres() {
    local_port=$1
    remote=$2
    remote_host=$(echo "$remote" | cut -d':' -f1)
    remote_port=$(echo "$remote" | cut -d':' -f2)
    ssh -L "${local_port}":localhost:"${remote_port}" "${remote_host}" -p 22
}

# Function to login to PostgreSQL using psql
sql_login() {
    psql -U schemamap "$@"
}

# Main script logic
case $1 in
    ssh-port-forward-postgres)
        if [ $# -ne 3 ]; then
            echo "Error: Missing arguments for ssh-port-forward-postgres."
            echo "Usage: $0 ssh-port-forward-postgres <local-port> <remote-host:remote-port>"
            exit 1
        fi
        ssh_port_forward_postgres "$2" "$3"
        ;;
    --help)
        show_help
        ;;
    sql)
        sql_login "$@"
        ;;
    *)
        echo "Error: Unknown command '$1'. Use --help for usage information."
        exit 1
        ;;
esac
