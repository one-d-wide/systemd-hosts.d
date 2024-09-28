#!/bin/sh
set -e

OPERATION=
HOST=
ADDR=
RESOLVER_SCRIPT=
RESOLVER="dig"
RESOLVER_OPTS="+short"
HOSTS_DIR="/etc/hosts.d"
FORCE=false
QUIET=false
DRY_RUN=false
PRIORITY=
PRIORITY_SET=false

REGEX_IPV4_WORD="[0-9]{1,3}"
REGEX_IPV4="($REGEX_IPV4_WORD\.){3}$REGEX_IPV4_WORD"
REGEX_IPV6_WORD="[0-9a-fA-F]{1,4}"
REGEX_IPV6_SUFF="($REGEX_IPV6_WORD:)*$REGEX_IPV6_WORD"
REGEX_IPV6="($REGEX_IPV6_WORD:){7}$REGEX_IPV6_WORD|($REGEX_IPV6_SUFF)?::($REGEX_IPV6_SUFF)?"

main() {
  parse_args "$@"

  case "$(get_op)" in
  create) create ;;
  move) move ;;
  delete) delete ;;
  resolve) resolve ;;
  list) list ;;
  *) fatal "Unknown operation: '$(get_op)'" ;;
  esac
}

description() {
  echo "A front-end to individually manipulate simple hosts.d entries"
  echo
}

usage() {
  default() {
    val="$(eval printf "\ \'%s\'" "\$$1")"
    test -n "$val" && echo "[default:$val]"
  }
  echo "Usage: $0 [OPERATION] [OPTIONS] [--] [ARGS]"
  echo "Operations:"
  echo "  -c, --create [HOST] [ADDR]"
  echo "  -m, --move [SRC_HOST] [DST_HOST]"
  echo "  -d, --delete [HOST]"
  echo "  -r, --resolve [HOST]"
  echo "  -l, --list [GLOB]"
  echo "Options:"
  echo "  -t, --target-dir <path> $(default HOSTS_DIR)"
  echo "  -p, --priority <priority>"
  echo "  -f, --force"
  echo "  -q, --quiet"
  echo "      --resolver-script <script>"
  echo "      --resolver <command> $(default RESOLVER)"
  echo "      --resolver-arg <arg> $(default RESOLVER_OPTS)"
  echo "      --resolver-erase-args"
  echo "      --dry-run"
}

SHORT_OPTS="hcmdrlt:p:fq"
LONG_OPTS="help,create,move,delete,resolve,list,target-dir:priority:,\
  force,quiet,dry-run,resolver-script:,resolver:,resolver-arg:,resolver-erase-args"

parse_args() {
  opts="$(getopt -n "$0" -o "$SHORT_OPTS" --long "$LONG_OPTS" -- "$@" || (usage >&2 && exit 1))"
  eval set -- "$opts"

  field_num=
  while [ $# != 0 ]; do
    opt="$1"
    shift

    # Parse fields
    if [ -n "$field_num" ]; then
      case "$(get_op):$field_num" in
      create:0 | move:0 | delete:0 | resolve:0 | list:0)
        case "$opt" in
        */*) fatal "Host can't contain '/': '$HOST'" ;;
        esac
        HOST="$opt"
        ;;
      create:1 | move:1) ADDR="$opt" ;;
      *) fatal_with_usage "Operation '$(get_op)' cant't take an additional field '$opt'" ;;
      esac
      field_num=$((field_num + 1))
      continue
    fi

    # Parse options
    case "$opt" in
    -h | --help) description && usage && exit 0 ;;
    -c | --create) set_op create ;;
    -m | --move) set_op move ;;
    -d | --delete) set_op delete ;;
    -r | --resolve) set_op resolve ;;
    -l | --list) set_op list ;;
    -t | --target-dir) HOSTS_DIR="$1" && shift ;;
    -p | --priority) PRIORITY="$1" && shift && PRIORITY_SET=true ;;
    -f | --force) FORCE=true ;;
    -q | --quiet) QUIET=true ;;
    --dry-run) DRY_RUN=true ;;
    --resolver-script) RESOLVER_SCRIPT="$1" && shift ;;
    --resolver) RESOLVER="$1" && shift ;;
    --resolver-arg) RESOLVER_OPTS="$RESOLVER_OPTS $(builtin printf "%q" "$1")" && shift ;;
    --resolver-erase-args) RESOLVER_OPTS= ;;
    --) field_num=0 ;;
    *) fatal "Unexpected value while parsing cli arguments: '$opt'" ;;
    esac
  done
}

set_op() {
  # Ensure that the operation is only set once
  if [ -n "$OPERATION" ]; then
    fatal "Can't redefine operation '$1' while '$OPERATION' is already set"
  fi
  OPERATION="$1"
}

get_op() {
  # Choose `create` as a default operation if none was specified
  test -z "$OPERATION" && set_op create
  printf "%s" "$OPERATION"
}

require_op() {
  get_op >/dev/null # Execute `get_op` directly, otherwise globals aren't assigned in sub shell
  for _op in "$@"; do
    test "$_op" = "$(get_op)" && return 0
  done
  return 1
}

fatal() {
  echo "Error: $*" >&2
  exit 1
}

fatal_with_usage() {
  (
    echo "Error: $*"
    usage
    exit 1
  ) >&2
}

missing() {
  fatal_with_usage "$* wasn't provided"
}

cat_file() {
  for _target in "$@"; do
    # Speed up concatenation by avoiding forking a process
    while read -r _line; do
      printf '%s\n' "$_line"
    done <"$_target"
  done
}

execute() {
  if [ "$QUIET" = false ]; then
    printf "Executing:"
    printf " '%s'" "$@"
    echo
  fi >&2
  command -- "$@"
}

check_hosts_dir() {
  test -e "$HOSTS_DIR" || fatal "Hosts directry doesn't exist: '$HOSTS_DIR'"
  test -d "$HOSTS_DIR" || fatal "Hosts directry isn't a directory: '$HOSTS_DIR'"
}

reset_target_file() {
  check_hosts_dir

  # Select an existing config file, possibly with assigned priority,
  # otherwise leave `TARGET` lave target a default location
  TARGET=
  ok=true
  prio_pat="[0-9][0-9]"
  for next_target in "$HOSTS_DIR"/$prio_pat"-$HOST.conf" "$HOSTS_DIR/$HOST.conf"; do
    # Skip glob if it wasn't matched
    if [ "$next_target" = "$HOSTS_DIR/$prio_pat-$HOST.conf" ]; then
      continue
    fi
    if [ -n "$TARGET" ] && [ -e "$next_target" ]; then
      echo "Found '$next_target', a duplicate of '$TARGET'"
      ok=false
    fi >&2
    if [ -z "$TARGET" ]; then
      TARGET="$next_target"
    fi
  done
  test -z "$TARGET" && fatal "Unreachable"
  test $ok != true && fatal "Detected ambiguity while selecting config files"

  # Substitute existing config with the one with the required priority level
  if [ $PRIORITY_SET = true ]; then
    new_prefix=
    case "$PRIORITY" in
    "") ;;
    [0-9][0-9]) new_prefix="$PRIORITY-" ;;
    *) fatal "Priority is invalid: '$PRIORITY'" ;;
    esac
    new_target="$HOSTS_DIR/$new_prefix$HOST.conf"
    if [ "$TARGET" != "$new_target" ] && [ -e "$TARGET" ]; then
      if [ $QUIET = false ]; then
        echo "Moving '$TARGET' to '$new_target'"
      fi
      if [ $DRY_RUN = false ]; then
        mv -n -- "$TARGET" "$new_target"
      else
        # Keep reference valid when performing dry-run
        new_target="$TARGET"
      fi
    fi
    TARGET="$new_target"
  fi

  # Check that we won't overwrite something unexpected
  if [ -e "$TARGET" ] && [ $FORCE != "true" ]; then
    # This isn't an absolutely fail-safe approach, but it should be sufficient,
    # considering that the target file name is already consists of the host.
    lnum=0
    spacers="$(printf ' \t')"
    while read -r _line; do
      lnum=$((lnum + 1))
      case "$line" in
      "") ;;
      *["$spacers"]"$HOST") ;;
      *["$spacers"]"$HOST"["$spacers"]*) ;;
      *)
        echo "Error on line $lnum of '$HOST.conf':"
        echo "The host record doesn't match required host name:"
        echo "## From $TARGET ##"
        printf "%s\n" "$line"
        if ! require_op move; then
          echo
          echo "Hint: Use '-f' or '--force' to overwrite anyways"
        fi
        exit 1
        ;;
      esac
    done <"$TARGET" >&2
  fi
}

delete() {
  test -z "$HOST" && missing Host

  reset_target_file
  test ! -e "$TARGET" && fatal "Host file doesn't exist: '$TARGET'"

  if [ $QUIET = false ]; then
    echo "Deleting '$TARGET'"
  fi
  if [ $DRY_RUN = false ]; then
    rm_args=
    test $FORCE = true && rm_args="-f"
    rm $rm_args -- "$TARGET"
  fi
}

create() {
  test -z "$HOST" && missing Host
  test -z "$ADDR" && missing Address

  if [ $FORCE = false ]; then
    if ! printf "%s" "$ADDR" | grep -qEo "^($REGEX_IPV4|$REGEX_IPV6)$"; then
      echo "Error: Provided address doesn't look like an IP address: '$ADDR'"
      echo "Hint: Use '-f' or '--force' to ignore this check"
      exit 1
    fi >&2
  fi

  reset_target_file

  record="$ADDR $HOST"
  if [ $QUIET = false ]; then
    echo "Writing '$record' to '$TARGET'"
  fi
  if [ $DRY_RUN = false ]; then
    touch -a "$TARGET" || fatal "Unnable to access $TARGET"
    printf '%s\n' "$record" >"$TARGET"
  fi
}

move() {
  test -z "$HOST" && missing Source
  test -z "$ADDR" && test $PRIORITY_SET = true && ADDR="$HOST"
  test -z "$ADDR" && missing Destination

  src_host="$HOST"
  dst_host="$ADDR"

  HOST="$src_host"
  reset_target_file
  src="$TARGET"

  test ! -e "$TARGET" && fatal "Source file doesn't exist: '$TARGET'"

  HOST="$dst_host"
  reset_target_file
  dst="$TARGET"

  val=
  pline=
  while read -r line; do
    if [ -n "$line" ]; then
      _val="$(printf "%s" "$line" | grep -o "^\s\?\S\+" || true)"
      if [ -n "$val" ] && [ "$_val" != "$val" ]; then
        echo "Error: Ambiguity in selecting address"
        echo "## From $src ##"
        printf "%s\n" "$pline"
        echo "..."
        printf "%s\n" "$line"
        exit 1
      fi >&2
      pline="$line"
      val="$_val"
    fi
  done <"$src"

  if [ -z "$val" ]; then
    echo "Source file doesn't contain requested address"
    echo "## From $src ##"
    cat_file "$src"
    exit 1
  fi >&2

  TARGET="$dst"
  HOST="$dst_host"
  ADDR="$val"
  create

  if [ "$src" != "$dst" ]; then
    TARGET="$src"
    HOST="$src_host"
    delete
  fi
}

resolve() {
  test -z "$HOST" && missing Domain

  resolve_with() {
    if [ -n "$RESOLVER_SCRIPT" ]; then
      execute "/proc/self/exe" "-c" "$RESOLVER_SCRIPT" -- "$HOST"
    else
      if ! command -V -- "$RESOLVER" >/dev/null 2>/dev/null; then
        fatal "Command '$RESOLVER' doesn't exist (hint: install 'bind' package)"
      fi
      execute "$RESOLVER" "$@" "$HOST"
    fi
  }
  ADDR="$(eval resolve_with "$RESOLVER_OPTS" || fatal "Resolver returned non-zero exit status")"
  if [ -z "$ADDR" ]; then
    fatal "Hostname resolution returned nothing. Does specified domain exist?"
  fi

  create
}

list() {
  check_hosts_dir

  test -z "$HOST" && HOST="*"
  for target in "$HOSTS_DIR"/$HOST.conf; do
    echo "## From $target ##"
    cat_file "$target"
    echo
  done
}

main "$@"
