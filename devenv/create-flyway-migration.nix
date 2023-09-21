{ writeScriptBin, ... }:
writeScriptBin "create_flyway_migration" ''
  # Description: Bash script to create Flyway migration script with a timestamp

  # Check if directory and description are provided
  if [ $# -lt 2 ]; then
      echo "Usage: $(basename $0) <directory> <description>"
      echo "Example: $(basename $0) ./schemamap_migrations 'add new table'"
      exit 1
  fi

  DIRECTORY=$1
  DESCRIPTION=$2

  # Create directory if it doesn't exist
  mkdir -p $DIRECTORY

  # Generate a timestamp
  TIMESTAMP=$(date +%Y%m%d%H%M%S)

  # Generate the filename
  FILENAME="V''${TIMESTAMP}__''${DESCRIPTION// /_}.sql"

  # Create an empty file with the filename
  touch $DIRECTORY/$FILENAME

  echo "Created Flyway migration script: $DIRECTORY/$FILENAME"
''
