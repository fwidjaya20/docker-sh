#!/bin/sh

# Author: win@payfazz.com

# Note:
# every code must compatible with POSIX shell

# this quote function copied from /lib/quote.sh, DO NOT EDIT
quote() (
  ret=; curr=; PSret=; tmp=; token=; no_proc=${no_proc:-n}; count=${count:--1};
  if ! ( count=$((count+0)) ) 2>/dev/null; then echo "count must be integer" >&2; return 1; fi
  case $no_proc in y|n) : ;; *) echo "no_proc must be y or n" >&2; return 1 ;; esac
  SEP=$(printf "\n \t"); nl=$(printf '\nx'); nl=${nl%x};
  for rest; do
    nextop=RN
    while [ "$count" != 0 ]; do
      case $nextop in
      R*) nextop="P${nextop#?}"
          token=${rest%%[!$SEP]*}; rest=${rest#"$token"}
          if [ -z "$token" ]; then token=${rest%%[$SEP]*}; rest=${rest#"$token"}; fi
          [ -z "$token" ] && [ -z "$rest" ] && [ -z "$curr" ] && break ;;
      PN) case $token in
          *[$SEP]*|'')
              nextop=RN; tmp=
              if [ -z "$token" ]; then [ -z "$rest" ] && tmp=y;
              else [ -n "$curr" ] && tmp=y; fi
              if [ "$tmp" ]; then ret="$ret'$curr' "; curr=; count=$((count-1)); fi ;;
          *)  case $no_proc in
              y)  ret="$ret$(printf %s\\n "$token" | sed "s/'/'\\\\''/g;1s/^/'/;\$s/\$/'/") "
                  count=$((count-1)); nextop=RN ;;
              n)  case $token in
                  *[\\\'\"]*)
                      tmp=${token%%[\\\'\"]*}; token=${token#"$tmp"}; curr="$curr$tmp"
                      case $token in
                      \\*) token=${token#\\}; nextop=PS; PSret=PN ;;
                      \'*) token=${token#\'}; nextop=PQ ;;
                      \"*) token=${token#\"}; nextop=PD ;;
                      esac ;;
                  *)  ret="$ret'$curr$token' "; curr=; count=$((count-1)); nextop=RN ;;
                  esac ;;
              esac ;;
          esac ;;
      PS) tmp=${token%"${token#?}"}; token=${token#"$tmp"}
          case $tmp in
          '') nextop=RS
              if [ -z "$rest" ]; then echo 'premature end of string' >&2; return 1; fi ;;
          $nl) nextop=$PSret ;;
          \\) nextop=$PSret; curr="$curr$tmp" ;;
          \") nextop=$PSret; curr="$curr$tmp" ;;
          \') nextop=$PSret
              if [ "$PSret" = PN ]; then curr="$curr'\\''"
              else curr="$curr\\'\\''"; fi ;;
          *)  nextop=$PSret;
              if [ "$PSret" = PN ]; then curr="$curr$tmp"
              else curr="$curr\\$tmp"; fi ;;
          esac ;;
      PQ) tmp=${token%%\'*}; token=${token#"$tmp"}; curr="$curr$tmp"
          case $token in
          \'*)  token=${token#\'}; nextop=PN ;;
          '')   nextop=RQ
                if [ -z "$rest" ]; then echo 'unmatched single quote' >&2; return 1; fi ;;
          *)    curr="$curr$token"; token= ;;
          esac ;;
      PD) tmp=${token%%[\\\'\"]*}; token=${token#"$tmp"}; curr="$curr$tmp"
          case $token in
          \"*)  token=${token#\"}; nextop=PN ;;
          '')   nextop=RD
                if [ -z "$rest" ]; then echo 'unmatched double quote' >&2; return 1; fi ;;
          *[\\\']*)
                tmp=${token%%[\\\']*}; token=${token#"$tmp"}; curr="$curr$tmp"
                case $token in
                \\*) token=${token#\\}; nextop=PS; PSret=PD ;;
                \'*) token=${token#\'}; curr="$curr'\\''" ;;
                esac ;;
          *)    curr="$curr$token"; token= ;;
          esac ;;
      *)  printf "BUG: quote: invalid nextop >%s<\n" "$nextop" >&2; return 1 ;;
      esac
    done
  done
  printf %s\\n "${ret% }"
)

exists() {
  case $1 in
  network|volume) [ "$(docker "$1" inspect -f ok "$2" 2>/dev/null)" = ok ] ;;
  *)              [ "$(docker inspect --type "$1" -f ok "$2" 2>/dev/null)" = ok ] ;;
  esac
}

running() {
  [ "$(docker inspect --type container -f '{{.State.Running}}' "$1" 2>/dev/null)" = true ]
}

construct_run_cmds() (
  ret="$(quote "${opts:-}") " || { echo 'cannot process "opts"' >&2; return 1; }
  eval "set -- $ret"
  for arg; do
    case $arg in
    --name|--net|--network) printf '"opts" cannot contain "%s"\n' "$arg" >&2; return 1 ;;
    esac
  done
  ret="$ret'--name' "
  [ -z "${name:-}" ] && { echo '"name" cannot be empty' >&2; return 1; }
  ret="$ret$(no_proc=y count=1 quote "$name") "
  [ -n "${net:-}" ] && ret="$ret'--network' $(no_proc=y count=1 quote "$net") "
  [ -z "${image:-}" ] && { echo '"image" cannot be empty' >&2; return 1; }
  ret="$ret$(no_proc=y count=1 quote "$image") "
  ret="$ret$(quote "${args:-}")" || { echo 'cannot process "args"' >&2; return 1; }
  ret=${ret# }
  ret=${ret% }
  printf %s "$ret"
)

gc_network() {
  [ "$(docker network inspect -f '{{index .Labels "kurnia_d_win.docker.autoremove"}}{{.Containers|len}}' "$1" 2>/dev/null)" = true0 ] \
  && docker network rm "$1" >/dev/null 2>&1
  return 0
}

exec_fn_opt() (
  if type "$1" 2>/dev/null | grep -q -F function; then
    "$@" || {
      tmp=$?
      printf '"%s" return %d\n' "$1" $tmp >&2
      return $tmp
    }
  fi
  return 0
)

main() (
  action=help
  [ $# -gt 0 ] && { action=$1; shift; }
  constructed_run_cmds=$(construct_run_cmds) || return $?
  case ${action:-} in
    name) echo "$name"; return 0 ;;
    image) echo "$image"; return 0 ;;
    net) echo "${net:-bridge}"; return 0 ;;
    show_cmds) echo "$constructed_run_cmds"; return 0 ;;

    start)
      if ! running "$name"; then
        if ! exists container "$name"; then
          exec_fn_opt "pre_$action" run || return $?
          [ -n "${net:-}" ] && ! exists network "$net" && {
            docker network create --driver bridge --label kurnia_d_win.docker.autoremove=true "$net" >/dev/null \
            || { printf 'cannot create network "%s"\n' "$net" >&2; return 1; }
          }
          eval "set -- $constructed_run_cmds"
          docker create --label "kurnia_d_win.docker.run_opts=$constructed_run_cmds" "$@" >/dev/null || return $?
          exec_fn_opt "pre_$action" created || return $?
          docker start "$name" >/dev/null || return $?
          exec_fn_opt "post_$action" run
        else
          exec_fn_opt "pre_$action" start || return $?
          docker start "$name" >/dev/null || return $?
          exec_fn_opt "post_$action" start
        fi
      fi
      return $?
      ;;

    stop|restart)
      if running "$name"; then
        eval "set -- $(no_proc=y quote "${stop_opts:-}" "$@")"
        tmp_opts=; i=1
        while [ $i -le $# ]; do
          a=$(eval echo "\${$i}")
          case $a in
          -t|--time)
            i=$((i+1)); a=$(eval echo "\${$i}")
            tmp_opts="$tmp_opts'--time' $(no_proc=y count=1 quote "$a") "
            ;;
          esac
          i=$((i+1))
        done
        exec_fn_opt "pre_$action" || return $?
        eval "set -- $tmp_opts"
        docker "$action" "$@" "$name" >/dev/null || return $?
        exec_fn_opt "post_$action"
      elif [ "$action" = restart ]; then
        echo 'container is not running' >&2
        return 1
      fi
      return $?
      ;;

    rm)
      if exists container "$name"; then
        eval "set -- $(no_proc=y quote "${rm_opts:-}" "$@")"
        tmp_opts=; i=1
        while [ $i -le $# ]; do
          a=$(eval echo "\${$i}")
          case $a in
            -[fvl]|-[fvl][fvl]|-[fvl][fvl][fvl]) tmp_opts="$tmp_opts$a " ;;
            --force|--volumes|--link) tmp_opts="$tmp_opts$a " ;;
          esac
          i=$((i+1))
        done
        saved_run_cmds=$(docker inspect -f '{{index .Config.Labels "kurnia_d_win.docker.run_opts"}}' "$name" 2>/dev/null)
        saved_run_cmds=$(no_proc=y quote "$saved_run_cmds")
        exec_fn_opt "pre_$action" || return $?
        docker rm $tmp_opts "$name" >/dev/null || return $?
        exec_fn_opt "post_$action" || return $?
        eval "set -- $saved_run_cmds"
        init_net=; i=1
        while [ $i -le $# ]; do
          a=$(eval echo "\${$i}")
          case $a in
          "'--network'")
            i=$((i+1)); a=$(eval echo "\${$i}")
            init_net=${a%"'"}
            init_net=${init_net#"'"}
            break
            ;;
          esac
          i=$((i+1))
        done
        [ -n "$init_net" ] && gc_network "$init_net" || :
      fi
      return $?
      ;;

    exec|exec_root)
      if running "$name"; then
        [ $# = 0 ] && { echo 'no command to execute' >&2; return 1; }
        tmp_opts='--interactive '
        [ "$action" = exec_root ] && tmp_opts="$tmp_opts--user 0:0 "
        [ -t 0 ] && [ -t 1 ] && [ -t 2 ] && tmp_opts="$tmp_opts--tty "
        exec docker exec $tmp_opts "$name" "$@"
      else
        echo 'container is not running' >&2
      fi
      return 1
      ;;

    kill)
      if running "$name"; then
        eval "set -- $(no_proc=y quote "${kill_opts:-}" "$@")"
        tmp_opts=; i=1
        while [ $i -le $# ]; do
          a=$(eval echo "\${$i}")
          case $a in
          -s|--signal)
            i=$((i+1)); a=$(eval echo "\${$i}")
            tmp_opts="$tmp_opts'--signal' $(no_proc=y count=1 quote "$a") "
            ;;
          esac
          i=$((i+1))
        done
        eval "set -- $tmp_opts"
        docker kill "$@" "$name" >/dev/null
      else
        echo 'container is not running' >&2
        return 1
      fi
      return $?
      ;;

    logs|port)
      if exists container "$name"; then
        docker "$action" "$name" "$@"
      else
        echo "container not exists" >&2
        return 1
      fi
      return $?
      ;;

    status)
      if exists container "$name"; then
        if [ "$(docker inspect -f '{{index .Config.Labels "kurnia_d_win.docker.run_opts"}}' "$name" 2>/dev/null)" != "$constructed_run_cmds" ]; then
          printf 'different_opts '
        fi
        if [ "$(docker inspect --type image -f '{{.Id}}' "$image" 2>/dev/null)" != "$(docker inspect --type container -f '{{.Image}}' "$name" 2>/dev/null)" ]; then
          printf 'different_image '
        fi
        if running "$name"; then
          printf 'running\n'
        else
          printf 'not_running\n'
        fi
      else
        printf 'no_container\n'
      fi
      return 0
      ;;

    show_running_cmds)
      if exists container "$name"; then
        docker inspect -f '{{index .Config.Labels "kurnia_d_win.docker.run_opts"}}' "$name" 2>/dev/null;
      else
        echo "container not exists" >&2
        return 1
      fi
      return $?
      ;;

    pull)
      docker pull "$image"
      return $?
      ;;

    update)
      if running "$name"; then
        pull=y
        force=n
        for arg; do
          case $arg in
          -n|--nopull) pull=n ;;
          -f|--force) force=y ;;
          -nf|-fn) pull=n; force=y ;;
          esac
        done
        [ "$pull" = "y" ] && docker pull "$image"
        echo "Recreating container ..." >&2
        if [ -z "$file" ]; then
          if [ "$force" = "y" ]; then
            "$0" stop && "$0" rm && "$0" start
          else
            case $("$0" status) in
            *different_*) "$0" stop && "$0" rm && "$0" start ;;
            esac
          fi
        else
          if [ "$force" = "y" ]; then
            "$0" "$file" stop && "$0" "$file" rm && "$0" "$file" start
          else
            case $("$0" "$file" status) in
            *different_*) "$0" "$file" stop && "$0" "$file" rm && "$0" "$file" start ;;
            esac
          fi
        fi
        return $?
      else
        echo 'container is not running' >&2
        return 1
      fi
      ;;

    help)
      cat <<EOF >&2
Available commands:
  start              Start the container
  stop               Stop the container
  restart            Restart the container
  rm                 Remove the container
  exec               Exec program inside the container
  exec_root          Exec program inside the container (as root)
  kill               Force kill the container
  logs               Show the log of the container
  port               Show port forwarding
  status             Show status of the container
  name               Show the name of the container
  image              Show the image of the container
  net                Show the primary network of the container
  show_cmds          Show the arguments to docker run
  show_running_cmds  Show the arguments to docker run in current running container
  pull               Pull the image
  update             pull the image and recreate container
                     if status return different_image or different_opts
  help               Show this message
EOF
      return 1
      ;;

  *)
    action="command_$action"
    if type "$action" 2>/dev/null | grep -q -F function; then
      "$action" "$@"
    else
      printf 'function "%s" not exists\n' "$action" >&2
      return 1
    fi
    return $?
    ;;
  esac
)

if grep -qF 6245455020934bb2ad75ce52bbdc54b7 "$0" 2>/dev/null; then
  if ! [ -r "${1:-}" ]; then
    printf 'Usage: %s <file> <command> [args...]\n' "$0" >&2
    exit 1
  fi
  file=$1; shift
  [ "${file#/}" = "$file" ] && file=$PWD/$file
  dir=$(cd "$(dirname "$file")" && pwd)
  file="$dir/$(basename "$file")"
  filename=$(basename "$file")
  dirname=$(basename "$dir")
  dirsum=$(printf %s "$dir" | cksum |  awk '{print $1}')
  . "$file" || exit 1
  if [ -z "$name" ]; then
    name=$dirname-$dirsum
  fi
  main "$@"
fi
