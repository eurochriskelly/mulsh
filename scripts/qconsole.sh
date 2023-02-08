#!/bin/bash
#
# Extract and upload workspaces to and from query console.
#

TS=$(date +%s)
QC_WORKDIR=$(pwd)
source $MULSH_TOP_DIR/scripts/common.sh

main() {
  #
  # show banner with name and version of tool
  #
  echo "--------------------------------------------------"
  echo "Query Console sync tool"
  echo "Version: $MULSH_VERSION"
  echo "--------------------------------------------------"
  echo ""
  if [ -z "$ML_HOST" ];then
    echo "Please source env.sh in top level directory to setup environment"
    return
  fi
  local option=$1
  doEval cleanupArtefacts "App-Services" 2>&1 > /dev/null
  case $option in
    pull | down | download)
      pullQueries
      ;;

    push | up | upload)
      pushQueries
      ;;

    list)
      listWorkspaces
      ;;

    *)
      echo "Unknown option [$option]"
      echo "Please select an option [push/pull/list]"
      echo "e.g."
      echo "qc push"
      cd $MULSH_TOP_DIR
      return
      ;;
  esac
}

processOptions() {
  option=$1
  shift
}

## option implementations
{
  listWorkspaces() {
    II "Checking server for workspaces."
    # Ask which workspace to download
    local workspace=
    local results=$(doEval getWorkspaces "App-Services")
    let i=1
    echo "Found the following workspaces with VALID names:"
    while read -r line; do
      local w=$(echo $line | awk -F, '{print $1}' )
      if [ -n "$w" ]; then
        echo "  " $i ": " $w
        let $((i++))
      fi
    done <<< "$results"
    echo -n "Choose a NUMBER to create workspace folder or press ENTER to exit: "
    read choice
    i=1
    if [ -n "$choice" ]; then
      local workspace=
      while read -r line; do
        w=$(echo $line | awk -F, '{print $1}' )
        if [ -n "$w" ]; then
          if [ "$i" == "$choice" ]; then
            workspace=$w
            break
          fi
          let $((i++))
        fi
      done <<< "$results"
      # ask user if they want to pull queries from the chosen workspace
      echo -n "Do you want to download workspace queries [$workspace] (y/n)? "
      read choice
      if [ "$choice" == "y" ]; then
        echo "Creating workspace folder: $workspace"
        mkdir -p $workspace
        cd $workspace
        pullQueries
        echo "Switch to workpsace folder with: 'cd $workspace'"
      fi
    fi
  }

  pullQueries() {
    II "Pulling queries from [$ML_HOST]."
    echo ""
    # TODO: Check if any files are newer than the _workspace.xml and, if yes, warn
    local workspace=
    local results=$(doEval prepWorkspaces "App-Services")
    local numRows=$(echo $results |wc -l)

    QC_WORKDIR=$(pwd)
    workspace=$(basename $QC_WORKDIR)

    if [ -n "$workspace" ]; then
      echo ""
      II "Downloading artefacts of workspace.. [$workspace]"
      local notFound=true
      for q in $results; do
        local parts=($(echo $q | sed 's/,/\n/g' | sed 's/ *$//g'))
        local selected="${parts[6]}"
        if [ "$workspace" == "$selected" ]; then
          notFound=false
          local type="${parts[0]}"
          local fname="${parts[1]}"
          if [ -n "${fname}" ]; then
            if [ "$type" == "Workspace" ]; then
              local uri="${parts[2]}"
              downloadWorkspace "$uri" "$fname" "App-Services"
            else
              local qid="${parts[2]}"
              local db="${parts[3]}"
              local order="${parts[4]}"
              local ext="${parts[5]}"
              downloadQuery "$qid" "$fname" "App-Services" "$db" "$ext"
            fi
          else
            EE "No filename [$fname]"
          fi
        fi
      done
      if "$notFound";then
        echo ""
        echo "Cannot pull workspace [$workspace] because it does not exist in server"
        echo ""
        echo "Available workspaces are:"
        echo "$results"|awk -F, '{print $7}'|sort|uniq | while read line;do
          echo " "$line
        done
        echo ""
        echo "Try renaming the /local folder/ or /workspace/ so they match."
        echo "Alternatively, import the /_workspace.xml/ to query console."
        echo""
      fi
    else
      echo "No workspace selected!"
    fi
  }

  # Push selected workspace
  pushQueries() {
    II "Pushing queries to query console."
    local workspace=
    QC_WORKDIR=$(pwd)
    workspace=$(basename $QC_WORKDIR)
    # Upload the workspace definition
    local wsLocal=./_workspace.xml
    if [ ! -f "$wsLocal" ]; then
      echo ""
      echo "WARNING: No local workspace file found. Please create in localhost and pull!"
      return
    fi

    echo ""
    II "Loading query changes to database."
    for f in $(find . -type f -name "*.xqy" -o -name "*.js" -o -name "*.sql" -o -name "*.spl"); do
      uploadUri $f /qcsync/${TS}/$(basename $f)
    done

    echo ""
    II "Uploading workspace to server."
    for f in $(find . -type f -name "*.xml"); do
      uploadUri $f /qcsync/${TS}/$(basename $f)
    done

    echo ""
    II "Updating workpaces and queries in database."
    doEval updateWorkspaces "App-Services" "{\"ts\":\"$TS\"}"
    echo ""
    echo "Reload the workspace in your browswer to see changes!"
    echo ""
  }
}

# common functions
{

  # Download contents of a query to a local file
  downloadQuery() {
    local qid=$1
    local uri="/queries/${qid}.txt"
    local fname=$2
    local db=$3
    local qdb=$4
    local ext=$5
    local opts=(-X GET)
    local dir=$(dirname $fname)
    local base=$(basename $fname)
    mkdir -p "$dir"
    echo "  Downloading query [$qid] to [$fname]"
    fetch "/v1/documents?uri=${uri}&database=${db}" "${opts[@]}" > "$fname"
  }

  downloadWorkspace() {
    local uri=$1
    local dir=$2
    local opts=(-X GET)
    local db="App-Services"
    mkdir -p "$dir"
    local fname="$dir/_workspace.xml"
    echo -n "" > $fname
    echo "  Downloading workspace [$uri] to [${fname/$MULSH_TOP_DIR\//}]"
    fetch "/v1/documents?uri=${uri}&database=${db}" "${opts[@]}" | sed '1d' >>"$fname"
  }

  # Upload contents of a text file to it's stored query
  uploadUri() {
    local fname=$1
    local uri=$2
    local opts=(
      -X PUT -T "$fname"
    )
    local db="App-Services"
    echo "  Uploading [${fname/$MULSH_TOP_DIR\//}] to [$uri]"
    fetch "/v1/documents?uri=${uri}&database=${db}" "${opts[@]}"
  }
}

main $@