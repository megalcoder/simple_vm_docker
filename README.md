# simple_vm_docker

A simple Ubuntu-based docker container. The user in the container is intended to be
the same as the user in the host system.

The purpose of this is to let beginners experience Linux system without messing up
their per-user configurations in their home directory.

The ```run.sh``` scripts automatically creates a single image, by defaule, called "meow."
Based on that, a container named by default "simple_vm" is created as a daemon.
It can be accessed via ```docker exec /bin/bash``` or ssh.

```
run.sh

```

## Prerequsite

Docker must be installed. The host user's account should be added to the ```docker``` group.

The following command should work:
```
docker run hello-world
```

Also, the container uses the man command of the docker host. Thus, the host

## Usage

```
run.sh [ssh,shell]
```

That will create the image, and container when needed, and connect to the container.
The user does not have to manually connect the container. Run.sh wraps the commands
to connect to the container.

```run.sh shell``` will connect to the container by using ```docker exec -it``` internally.
```run.sh ssh``` will use ```ssh -p <docker ssh port> <docker user id>@<docker ip address>```
by default. ```run.sh``` is the same as ```run.sh ssh```.


```
run.sh stop
```

The command will delete the container

```
run.sh rm
```

The command will stop the container if any, and delete the image

## Man page

The image is based on minimized Ubuntu, which misses manpage. Thus, man command actually
invokes a script that does:
```
ssh id@host_ip "man $@"
```

ssh from container to host is solely for that purpose.

## Automatic Image Creation

```run.sh``` will automatically rebuild the image, and container before connecting the container
via ```docker exec``` or ```ssh```. How does it work?

Whenever an image is created, it gets a timestamp, which is compared to the timestamp of the clone:
```
    if ! docker build -t ${img_name} \
	     --label CreationTime=${time_stamp} \
```

The comparison is here:
```
    local docker_dir_time="$(stat -c %y ${docker_build_dir} | cut -d ' ' -f1-2 | sed  's/ /T/g')"
    docker_dir_time="${docker_dir_time}Z"
    local img_creation_time="$(docker inspect -f '{{.Config.Labels.CreationTime}}' meow)"
    # if docker dir modified after img created
    if [[ $docker_dir_time > $img_creation_time ]]; then
```

After rebuilding the image if needed, a daemon container is created. If there exists a daemon container
and the image wasn't rebuilt, the container is not being re-created.

## Host Home Directories Shared With The Container

See ```run_container_as_daemon```. A few more directories could be added and shared.