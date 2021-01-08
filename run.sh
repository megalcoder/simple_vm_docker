#!/bin/bash

# Change these if you want to override
container_name="simple_vm_$USER"
img_name="meow_$USER"
ssh_custom_port=${SSH_CUSTOM_PORT:-"2222"}

function show_help() {
    echo "To run:  $0 [ssh,shell]"
    echo "To stop: $0 stop"
}

function sanity_check() {
    if (($# > 1)); then
        echo "Wrong usages." 1>&2
        show_help 1>&2
        exit 5
    fi
    local -a required_apps=("docker" "man")
    for prog in "${required_apps[@]}"; do
        if ! which $prog > /dev/null 2>&1; then
            echo "$prog should be installed in the server" 1>&2
            echo "please contact the system administrator" 1>&2
            exit 10
        fi
    done
    return 0
}

function get_script_dir() {
    local script_dir="$(dirname ${BASH_SOURCE[0]})"
    echo "$(realpath -s ${script_dir})"
}

sanity_check "$@"

docker_build_dir=$(get_script_dir)
docker_user=${USER:-"$(id -un)"}
docker_user_uid=${USER_UID:-"$(id -u)"}
cmd=${1:-"ssh"}

function is_container_running() {
    local container_name=$1
    if docker ps | egrep ${container_name} > /dev/null 2>&1; then
	    return 0
    fi
    return 1
}

function stop_container_if_any() {
    local container_name=$1
    if ! is_container_running "$container_name"; then
	    return 0
    fi
    if docker rm -f ${container_name} > /dev/null; then
        echo "${container_name} has been stopped successfully"
    fi
}

# create the image and/or run container
function run_container_as_daemon() {
    local container_name="$1"
    local img_name="$2"
    local -n home_dirs_to_mnt=$3
    local -a v_opts=()
    for subdir in ${home_dirs_to_mnt[@]}; do
        if [[ -f $HOME/$subdir ]] || [[ -d $HOME/$subdir ]]; then
            v_opts+=("-v $HOME/$subdir:$HOME/$subdir ")
        fi
    done
    docker run -d --rm \
	       --name ${container_name} ${v_opts[@]} \
	       -it ${img_name}:latest /bin/bash > /dev/null 2>&1
    return $?
}

function build_img() {
    local img_name=$1
    local docker_build_dir=$2
    local time_stamp="$(date "+%Y-%m-%dT%H:%M:%S.000000000Z")"
    echo "Preparing your virtual machine..."
    echo "Please be patient..."
    pushd ${docker_build_dir} > /dev/null 2>&1
    echo building ${img_name}
    if ! docker build -t ${img_name} \
	     --label CreationTime=${time_stamp} \
         --build-arg NEW_USER=${docker_user} \
         --build-arg NEW_USER_UID=${docker_user_uid} \
         --build-arg SSH_PORT=${ssh_custom_port} \
	     -f Dockerfile . 2>&1 | egrep "^(Step)"; then
        echo docker build failed 1>&2
        exit 1
    fi
    echo ${img_name} is successfully created
    echo ""
    popd > /dev/null 2>&1
}

function is_img_exist() {
    if docker images 2>&1 | egrep $1 > /dev/null 2>&1; then
        return 0
    fi
    return 1
}

function is_build_img() {
    local img_name=$1
    local docker_build_dir=$2
    # image isn't exist
    if ! is_img_exist "${img_name}"; then
        echo "${img_name} does not exist, needs rebuild"
	    return 0
    fi
    local docker_dir_time="$(stat -c %y ${docker_build_dir} | cut -d ' ' -f1-2 | sed  's/ /T/g')"
    docker_dir_time="${docker_dir_time}Z"
    local img_creation_time="$(docker inspect -f '{{.Config.Labels.CreationTime}}' ${img_name})"
    # if docker dir modified after img created
    if [[ $docker_dir_time > $img_creation_time ]]; then
	    echo "The current virtual image is outdated, and needs rebuild"
	    echo "The virtual machine image was created:"
	    echo "  : ${img_creation_time}"
	    echo "The blue print for the virtual machine image was modified"
	    echo "  : ${docker_dir_time}"
	    return 0
    fi
    return 1
}

function update_host_authroized_key() {
    local script_dir="$(get_script_dir)"
    pushd $script_dir > /dev/null 2>&1
    local -a files=("id_rsa.pub" "id_dsa.pub")
    if ! [[ -f ~/.ssh/authorized_keys ]]; then
        touch ~/.ssh/authorized_keys
        chmod 600 ~/.ssh/authorized_keys
    fi
    for f in ${files[@]}; do
        local ln_cnt="$(comm -123 <(sort ./${f}) <(sort ~/.ssh/authorized_keys) | wc -l)"
        if [[ $ln_cnt == "0" ]]; then
            cat ./${f} >> ~/.ssh/authorized_keys
        fi
    done
    popd > /dev/null 2>&1
}

function do_ssh() {
    update_host_authroized_key
    local id=$1
    local name=$2
    local script_dir="$(get_script_dir)"
    local ip="$(docker inspect --format='{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${container_name}")"
    (cd $script_dir; ssh -i ./id_rsa -p 2222 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${id}@${ip})
}

function rm_images() {
    if is_img_exist "$1"; then
        docker rmi $1
        return $?
    fi
}

function prepare_container() {
    local img_name=$1
    local container_name=$2
    local docker_build_dir=$3

    if is_build_img ${img_name} ${docker_build_dir}; then
        echo "Stopping the ${container_name} if exists"
        stop_container_if_any ${container_name}
        echo "Now, building your new virtual machine image"
        build_img "${img_name}" "${docker_build_dir}"
    fi

    local -a home_dirs2mnt=(
        "workspace"
        "tmp"
        "Desktop"
        "Documents"
        "Downloads"
        "Music"
        "Pictures"
        "Public"
        "Templates"
        "Videos")

    echo "WARNING: $HOME is not saved"
    echo "WARNING: The following directories are saved:"
    echo ${home_dirs2mnt[@]} | fold -w 40 -s | sed 's/^/           /g'
    if ! is_container_running ${container_name}; then
        run_container_as_daemon ${container_name} ${img_name} home_dirs2mnt
    fi
}

case "$cmd" in
    stop)
        stop_container_if_any ${container_name}
        ;;
    rm)
        stop_container_if_any ${container_name}
        rm_images ${img_name}
        ;;
    shell)
        prepare_container "${img_name}" "${container_name}" "${docker_build_dir}"
        docker exec -it ${container_name} /bin/bash
        ;;
    ssh|"")
        prepare_container "${img_name}" "${container_name}" "${docker_build_dir}"
        do_ssh ${docker_user} ${container_name}
        ;;
    help|-h|--help)
        show_help
        exit 0
        ;;
    *)
        echo "Wrong usage" 1>&2
        show_help 1>&2
        exit 1
        ;;
esac

