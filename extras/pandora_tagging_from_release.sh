#!/bin/sh
#

SF_FILES_URL=https://sourceforge.net/projects/pandora/files/
BUILD_INFO="agent_unix	pandora_agents/unix	BUILD	COMMIT
console	pandora_console	BUILD	COMMIT
server	pandora_server	BUILD	COMMIT"

PANDHOME_ENT=/dev/null/PANDHOME_ENT

: ${CODEHOME:=$(realpath "${0%/*}"/..)}
: ${WORKDIR:=/var/tmp/pandora_tagging_from_release}
: ${DISTDIR:=$WORKDIR/distfiles}
: ${TMPDIR:=$WORKDIR/tmp}
: ${LOGLEVEL:=3}

GIT_VERBOSE_OPTS="--quiet"

#######################################
# Show usage and exit as required
# Globals:
#   None
# Arguments:
#   $1 - exit status.  don't exit if empty
#   $2 - extra message print before usage
# Returns:
#   None
#######################################
usage() {
  local ex_stat="$1"
  local msg="$2"
  [ "$msg" ] && echo "$msg" && echo
  cat <<USAGE
Usage: $0 <VERSION>
USAGE
  [ "$ex_stat" ] && exit $ex_stat
}

#######################################
# Show messgae to stderror as log
# Globals:
#   LOGLEVEL
# Arguments:
#   $1 - log level of this message.
#   $2 - message to print
#   $3 - output color if specified
# Returns:
#   None
#######################################
log() {
  local level=$1
  local log="$2"
  local color=$3

  if [ $LOGLEVEL -ge $level ]; then
    case "$color" in
      red)   fmt="[0;31m%s[0m";;
      green) fmt="[0;32m%s[0m";;
      yellow)fmt="[0;33m%s[0m";;
      blue)  fmt="[0;34m%s[0m";;
      white) fmt="[0;37m%s[0m";;
      *)     fmt='%s';; 
    esac
    printf "$fmt\n" "$log" >&2
  fi
}

#######################################
# Test $1 starts with $2 or not
# Globals:
#   None
# Arguments:
#   $1 - string to test
#   $2 - string 
# Returns:
#   None
#######################################
starts_with() {
  test "${1#$2}" != "${1}"
}

#######################################
# Make abbreviated commit hash string
# Globals:
#   None:
# Arguments:
#   $1 - commit hash to abbrev
# Returns:
#   STDOUT - abbreviated commit hash
#######################################
abbrev_commit() {
  local hash="$1"
  echo "$hash" | cut -b 1-10
}


#######################################
# Globals:
# Arguments:
#   $1 - version
# Returns:
#   branch
#######################################
get_branch_for_version() {
  case $version in
    6.0SP*) echo pandora_6.0;;
    *) echo develop;;
  esac
}
#######################################
# Globals:
# Arguments:
# Returns:
#######################################
main() {
  local version remote_tags
  local build commit branch

  [ "${version:=$1}" ] || usage 64 ""

  # Get build number from release tarballs

  log 1 "===> Check official tag first" white

  remote_tags=$(git ls-remote --tags https://github.com/pandorafms/pandorafms.git | grep "refs/tags/$version")
  if [ "$remote_tags" ]; then
    log 1 "Tag $version already exist on remote. Do noting."
    log 3 "$remote_tags" blue
    exit
  fi

  log 1 "===> Get build number for each components" white

  update_build_numbers $version

  branch=$(get_branch_for_version $version)

  for build in $(echo "$BUILD_INFO" | awk ' $3 != "BUILD" { print $3 }' | sort -u)
  do
    log 1 "===> Search release commit for build $build: $(get_component_names_by build $build)" white

    git checkout --force $GIT_VERBOSE_OPTS $branch
    git reset $GIT_VERBOSE_OPTS --hard HEAD

    commit=$(search_commit_for_build $version $build $branch)
    
    if [ -z "$commit" ]; then
      log 1 "No suitable commit found" red
      continue
    fi
    BUILD_INFO=$(echo "$BUILD_INFO" | sed "/$build	COMMIT/s/COMMIT/$commit/")
  done

  do_tagging "$version"
}

#######################################
# get compenent names filtered by specified criteria
# Globals:
#   BUILD_INFO
# Arguments:
#   $1 - field for filtering
#   $2 - value
# Returns:
#   list of names separated by space
#######################################
get_component_names_by() {
  local by="$1"
  local value="$2"
  local filter

  case $by in
    path) filter="\$2 == \"$value\"";;
    build) filter="\$3 == \"$value\"";;
    commit) filter="\$4 == \"$value\"";;
    *) filter=''
  esac
  echo "$BUILD_INFO" | awk "$filter"'{ printf " %s", $1 }'
}

#######################################
# Globals:
# Arguments:
# Returns:
#######################################
get_last_commit_of_day() {
  local day="$1"
  shift
  git log "$@" \
    --pretty=%H -1 \
    --after="$( date -d "$day"         +'%Y-%m-%d') 00:00:00 +02:00" \
    --before="$(date -d "$day + 1 day" +'%Y-%m-%d') 00:00:00 +02:00"
}

#######################################
# Search commit ID which has same contents
# with release tarball
# Globals:
#   TMPDIR
# Arguments:
#   $1 - version string
#   $2 - build
# Returns:
#   build number (YYMMDD) 
#######################################
search_commit_for_build() {
  local base commit commits
  local candidates ncommits i
  local dirs n_differs

  local version="$1"
  local build="$2"
  local branch="$3"

  # リリースを探す基点となるコミット番号を取得
  # ビルド日の最後のコミット
  base=$(get_last_commit_of_day "20$build" --first-parent $branch)
  # ない場合はビルド日の翌日以降前の最初のコミット
  : ${base:=$(git log --first-parent $branch --pretty=%H --reverse \
                      --after="$(date -d "20$build + 1 day" +'%Y-%m-%d') 00:00:00 +02:00" | head -1)}
  # それもない場合はビルド日以前の最新のコミット
  : ${base:=$(git log --first-parent $branch --pretty=%H -1 \
                      --before="$(date -d "20$build" +'%Y-%m-%d') 00:00:00 +02:00")}
  if [ -z "$base" ]; then
    log 3 "Failed to determine commit for starting point" red
    return
  fi

  # ビルド日以降のマージに含まれるコミットを除外するため基点コミットをチェックアウト
  # (--first-parent を指定する場合は不要かもしれない)
  #git checkout --force $GIT_VERBOSE_OPTS $base
  #git reset $GIT_VERBOSE_OPTS --hard HEAD

  # ビルド日の前日の最後のコミット
  commit=$(get_last_commit_of_day "20$build - 1day" --first-parent)
  # ない場合はビルド日以前の最新のコミット
  : ${commit:=$(git log --first-parent $branch --pretty=%H -1 \
                        --before="$(date -d "20$build" +'%Y-%m-%d') 00:00:00 +02:00")}

  if [ -z "$commit" ]; then
    log 3 "No suitable commit found for start" red
    return
  fi
  log 5 "Search commits $(abbrev_commit $commit)..$(abbrev_commit $base)" 

  # 基点からビルド番号の日の最後のコミットまでを順にチェック
  dirs=$(echo "$BUILD_INFO" | awk "\$3 == \"$build\" { printf \" %s\", \$2 }")
  commits=$(git log $commit..$base --pretty=%H --first-parent -- $dirs)

  if [ -z "$commits" ];then
    log 1 "No commits found for build" red
    return
  fi

  log 5 ">>> extract release file for comparison as required"

  local name subdir dest
  [ -d $TMPDIR ] && rm -rf $TMPDIR
  for name in $(get_component_names_by build $build)
  do
    subdir=$(echo "$BUILD_INFO" | awk "\$1 == \"$name\" {print \$2}")
    dest=$TMPDIR/release/$subdir/..
    [ ! -d $dest ] && mkdir -p $dest
    tar zxf $(get_distfile $name $version) -C "$dest"
  done

  candidates=""
  i=0
  ncommits=$(echo "$commits"|wc -l)

  for commit in $commits
  do
    i=$(($i + 1))
    log 1 "====>> ($i/$ncommits) $(git show $commit -s --pretty="testing commit %h (%ad) %s")" white
    n_differs=$(test_commit $commit $version "$dirs")
    if [ $? -eq 0 ];then
      if [ "$n_differs" -eq 0 ]; then
        log 3 "Use $(abbrev_commit $commit) for tagging $version (build=$build)"
        echo $commit
        return
      fi
      candidates="${candidates}$n_differs $commit;"
    elif [ "$candidates" ]; then
      log 3 "Candidate(s) exist. use one of them"
      break 
    fi
  done

  if [ "$candidates" ];then
    candidates=$(echo "$candidates"|tr ';' '\n')
    commit=$(echo "$candidates" | sort -n | awk 'NR == 1 { print $2 }')
    if [ $(echo "$candidates" | wc -l) -gt 1 ]; then
      log 3 <<-MSG
	More than one suitable commits found:
	$candidates
	MSG
    fi
    log 3 "Use commit less differ from release: $commit"
    echo "$commit"
  fi
}

#######################################
# Globals:
# Arguments:
# Returns:
#   number of lines removed and added
#######################################
test_commit() {
  local commit=$1
  local version="$2"
  local paths="$3"

  local current_commit=$(git rev-parse HEAD)

  git checkout $GIT_VERBOSE_OPTS --force $commit
  git reset $GIT_VERBOSE_OPTS --hard HEAD

  log 3 ">>> Compare as-is"
  make_distfile_tree "$paths" "$TMPDIR/$commit"

  differs=$(diff -ur $TMPDIR/$commit $TMPDIR/release 2>&1)

  del=$(echo "$differs" | grep '^-' | grep -v "^-\{3\} $TMPDIR/$commit" | wc -l)
  add=$(echo "$differs" | grep '^[+]' | grep -v "^[+]\{3\} $TMPDIR/release" | wc -l)
  echo $(($del+$add))

  if [ "$differs" ];then
    n_differs=$(diff -qr $TMPDIR/$commit $TMPDIR/release 2>&1 | wc -l)
    differs=$(diff -ur $TMPDIR/$commit $TMPDIR/release 2>&1)
    log 3 "$n_differs file(s) different" yellow
    log 3 "$differs" blue
    log 3 ">>> Compare with version adjusted files"
  
    path_regex=$(echo $paths | tr ' ' '|')
    pandora_update_version "$TMPDIR/$commit" "final" "$version" "$build" >/dev/null 2>&1
#    | while read line
#    do
#      continue
#      case "$line" in
#        *$PANDHOME_ENT*);;
#        *$TMPDIR/$commit/*) echo "$line" | egrep "$path_regex" >/dev/null && log 3 "$line" ;;
#        *)                  log 3 "$line";;
#      esac
#    done

    n_differs=$(diff -qr $TMPDIR/$commit $TMPDIR/release 2>&1 | wc -l)
    if [ $n_differs -eq 0 ];then
      log 3 "$commit can be a release commit" yellow
    else
      log 3 "$n_differs file(s) are different" yellow
      log 3 "This is not a release commit" red
    fi
  else
    log 3 "$commit is exactly same as release files." green
  fi
  rm -rf $TMPDIR/$commit
  [ -z "$differs" ] || [ "$n_differs" -eq 0 ]
  return $?
}

#######################################
# Get build number from release tarball
# Globals:
#   None
# Arguments:
#   $1 - name of component
#   $2 - version string
# Returns:
#   build number (YYMMDD) 
#######################################
get_build_number() {
  local name=$1
  local version=$2
  local f=$(get_distfile $name $version)

  [ -z "$f" ] && return 1

  case "$name" in
    agent_unix) tar zxf $f -O unix/pandora_agent_installer | grep '^PI_BUILD' | grep -o '[0-9]*';;
    server)     tar zxf $f -O pandora_server/pandora_server_installer | grep '^PI_BUILD' | grep -o '[0-9]*';;
    console)    tar zxf $f -O pandora_console/install.php | grep '^\$build =' | grep -o '[0-9]*';;
  esac
}

#######################################
# BUILD_INFO 中の BUILD を実際のビルド番号に置き換える
# Globals:
#   BUILD_INFO
# Arguments:
#   $1 - version string
# Returns:
#   None
#######################################
update_build_numbers() {
  local name build result
  local version="$1"

  for name in $(echo "$BUILD_INFO" | awk '{ print $1 }')
  do
    build=$(get_build_number $name $version)
    if [ "$build" ]; then
      BUILD_INFO=$(echo "$BUILD_INFO" | sed "/^$name/s/BUILD/$build/")
      log 3 "$name=$build"
    else
      log 1 "Failed to get build number of $name, $version" yellow
      return
    fi
  done
}

#######################################
# Do tagging
# Globals:
#   None
# Arguments:
#   $1 - list of "git tag" command lines seperated by semicolon
# Returns:
#   None
#######################################
do_tagging () {
  local commit cmds old_tags ref
  local version="$1"

  log 1 "===> Create/Update tags" white

  if echo "$BUILD_INFO" | grep 'COMMIT$' >/dev/null; then
    log 3 "Commit not found for: $(echo "$BUILD_INFO" | grep 'COMMIT' | cut -f 1 | tr '\n' ' ')" red
    exit
  fi

  old_tags=$(git tag -l "$version*")
  log 3 "current tags: $old_tags"

  commit=$(echo "$BUILD_INFO" | cut -f 4 | sort -u)
  if [ $(echo "$commit" | wc -l) -eq 1 ];then
    log 3 "All components have same commit: $(abbrev_commit $commit)"
    cmds="git tag --force $version $commit"
  else
    cmds=$(echo "$BUILD_INFO" | awk '{ print "git tag --force '$version'-" $1 " " $4 }')
  fi

  # check old tags that to be removed, has same hash with new tag
  local tag new_tag_cmd new_commit
  if [ "$old_tags" ];then
    log 3 ">>> Check commit hash between current and new tag" 

    while read commit ref
    do
      tag=${ref#refs/tags/}
      new_hash=$(echo "$cmds" | grep "$tag" | awk '{ print $NF }')
      if [ "$new_hash" ]; then
        if [ "$commit" = "$new_hash" ]; then
          log 3 "Already exist tag '$tag' with same commit ($(abbrev_commit $commit))"
          cmds=$(echo "$cmds" | egrep -v "$tag $commit")
        else
          # nothing to do. (since --force option specified)
          :
        fi
      else
        # remove tag not in $cmds
        git tag -d $tag
      fi
    done <<-EOF
	$(git show-ref $old_tags)
	EOF
  fi

  log 3 '>>> Execute "git tag"'
  if [ "$cmds" ];then
    log 3 "$cmds" blue
    eval "$cmds"
  else
    log 3 "Noting to do" blue
  fi
}

#######################################
# Globals:
# Arguments:
# Returns:
#######################################
download_distfile() {
  local name=$1
  local version=$2
  local v_major v_minor url curl_log_opt ret
  local loglv=3
  local filename="pandorafms_$name-${version}.tar.gz"

  log $loglv "===> Download release tarball $name" white

  if starts_with $version "7.0NG"; then
    v_major=7.0NG
    v_minor="${version#7.0NG.}"
    : ${v_minor:=Final}
    url="${SF_FILES_URL}Pandora%20FMS%20${v_major}/${v_minor}/Tarball/$filename/download"
  elif starts_with $version "6.0"; then
    v_major=6.0
    v_minor="${version#6.0}"
    # 6.0SP7's release files are uploaded under SP7Final/SP7Final :(
    if [ $v_minor = "SP7" ]; then
      v_minor="SP7Final/SP7"
    fi
    url="${SF_FILES_URL}/Pandora%20FMS%20${v_major}/${v_minor}Final/Tarball/$filename/download"
  fi

  if [ -z "$url" ];then
    log $loglv "Unsupported version: $version" red
    return 1
  fi

  [ $LOGLEVEL -ge $loglv ] && curl_log_opt=--progress-bar || curl_log_opt=--silent
  curl $curl_log_opt -Lo "$DISTDIR/$filename" "$url"
  [ ${ret:=$?} -ne 0 ] && log $loglv "Failed to download file: $url" red
  return $ret
}

#######################################
# Returns release tarball path. if file does not exist in $DISTDIR,
# download first.
#
# Globals:
#   DISTDIR
# Arguments:
#   $1 - name of component
#   $2 - version string
# Returns:
#   full path of downloaded tarball
#######################################
get_distfile() {
  local name=$1
  local version=$2
  local f="$DISTDIR/pandorafms_$name-$version.tar.gz"

  # download as required
  [ ! -f $f ] && download_distfile $name $version

  [ -f $f ] && echo "$f"
}

#######################################
# Globals:
# Arguments:
# Returns:
#######################################
pandora_update_version() {
  local codehome="$1"
  shift 
  sed -e '/^source build_vars.sh$/d' $CODEHOME/extras/pandora_update_version.sh \
    | env CODEHOME="$codehome" PANDHOME_ENT=$PANDHOME_ENT bash -s "$@"
}

#######################################
# Globals:
# Arguments:
# Returns:
#######################################
make_distfile_tree() {
  local sources="$1"
  local dest_base="$2"
  local basename dirname dest

  for src in $sources
  do
    src="./$src"
    dirname="${src%/*}"
    basename="${src##*/}"

    dest="$dest_base/${dirname#.}"
    [ -d "$dest" ] || mkdir -p "$dest"

    cmd=$(sed -n '\,^cd $CODEHOME'"${dirname#.} && tar .* $basename, "'{ s/[zvc]\{3\}f .*.tar.gz/cf - --exclude "sed*"/; s/ *|| exit 1$//; p; }' $CODEHOME/extras/build_src.sh)
    eval "($cmd)" | tar xf - -C "$dest"
  done
}



#
# main
#

(cd $CODEHOME && main "$@")

