#!/usr/bin/env bash

# Function to display help information
show_help() {
    echo "Usage: $0 [command] [options]"
    echo "Commands:"
    echo "  port-forward-postgres <rathole-config.toml>  Forward local TCP IPV4 port to pgtunnel.eu.schemamap.io"
    echo "  --help                                       Show this help message"
    echo "  sql                                          Login to the default database with the schemamap user using psql CLI"
}

port_forward_postgres() {
    rathole -c "$1"
}

sql_login() {
    psql -U schemamap "$@"
}

# Main script logic
case $1 in
    port-forward-postgres)
        if [ $# -ne 2 ]; then
            echo "Error: Missing arguments for port-forward-postgres."
            echo "Usage: $0 port-forward-postgres <rathole-config.toml>"
            exit 1
        fi
        port_forward_postgres "$2"
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
